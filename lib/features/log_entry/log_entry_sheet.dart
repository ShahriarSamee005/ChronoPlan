import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ai/groq_service.dart';
import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/log_entries_provider.dart';
import '../../providers/settings_provider.dart';

/// Elapsed hours of today that hold no USER-logged activity, for the
/// missing-hours quick-pick strip.
///
/// Screen-time rows (`isUsageDerived == true`) do NOT count as covering an
/// hour: confirming OS screen time is not the same as the user accounting for
/// their own time, so such an hour stays "missed" until they log it themselves.
///
/// [now] defaults to `DateTime.now()`; only hours strictly before `now.hour`
/// are considered, so the in-progress hour is never reported.
List<int> computeMissedHours(List<LogEntry> entries, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final missed = <int>[];
  for (int h = 0; h < reference.hour; h++) {
    final slotStart = today.add(Duration(hours: h));
    final slotEnd = slotStart.add(const Duration(hours: 1));
    final covered = entries.any(
      (e) =>
          !e.isUsageDerived &&
          e.startTime.isBefore(slotEnd) &&
          e.endTime.isAfter(slotStart),
    );
    if (!covered) missed.add(h);
  }
  return missed;
}

class LogEntrySheet extends ConsumerStatefulWidget {
  final LogEntry? existing;

  const LogEntrySheet({super.key, this.existing});

  @override
  ConsumerState<LogEntrySheet> createState() => _LogEntrySheetState();
}

class _LogEntrySheetState extends ConsumerState<LogEntrySheet> {
  final _descCtrl = TextEditingController();

  late DateTime _startTime;
  late DateTime _endTime;
  int? _selectedCategoryId;
  bool _isSaving = false;

  // B5 category suggestion
  Timer? _debounceTimer;
  String? _suggestedCategoryName;
  bool _isSuggesting = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _descCtrl.text = e.description;
      _startTime = e.startTime;
      _endTime = e.endTime;
      _selectedCategoryId = e.categoryId;
    } else {
      _startTime = _defaultStart();
      _endTime = _startTime.add(const Duration(hours: 1));
    }
    _descCtrl.addListener(_onDescriptionChanged);
  }

  /// Defaults to the last completed hour — e.g. at 6:45 PM → 5:00 PM–6:00 PM.
  DateTime _defaultStart() {
    final now = DateTime.now();
    if (now.hour > 0) {
      return DateTime(now.year, now.month, now.day, now.hour - 1);
    }
    // Midnight edge case: yesterday 23:00
    final yesterday = now.subtract(const Duration(days: 1));
    return DateTime(yesterday.year, yesterday.month, yesterday.day, 23);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(categoriesProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayEntries =
        ref.watch(logEntriesForDayProvider(today)).valueOrNull ?? [];
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    final missedHours =
        widget.existing == null ? computeMissedHours(todayEntries) : <int>[];

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: GlassCard(
        borderRadius: 28,
        opacity: 0.20,
        blurSigma: 16,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Sleep toggle ──────────────────────────────────────────
                const _SleepToggleRow(),
                const SizedBox(height: 14),

                // ── Missed hours strip ────────────────────────────────────
                if (missedHours.isNotEmpty) ...[
                  _MissedHoursStrip(
                    hours: missedHours,
                    selectedHour: _startTime.hour,
                    onTap: (h) {
                      setState(() {
                        _startTime = today.add(Duration(hours: h));
                        final end = _startTime.add(const Duration(hours: 1));
                        _endTime = end.isAfter(now) ? now : end;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Header ───────────────────────────────────────────────
                if (widget.existing == null)
                  Text(
                    'Logging: ${_fmt(_startTime)} – ${_fmt(_endTime)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  )
                else
                  const Text(
                    'Edit Entry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 20),

                // ── Time range ────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _TimeButton(
                        label: 'Start',
                        time: _startTime,
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                    ),
                    Expanded(
                      child: _TimeButton(
                        label: 'End',
                        time: _endTime,
                        onTap: () => _pickTime(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Description ───────────────────────────────────────────
                TextField(
                  controller: _descCtrl,
                  decoration: InputDecoration(
                    hintText: 'What were you doing?',
                    labelText: 'Description',
                    suffixIcon: catsAsync.hasValue
                        ? IconButton(
                            icon: const Icon(Icons.auto_awesome_rounded,
                                size: 18),
                            color: Colors.white54,
                            tooltip: 'Parse from text',
                            onPressed: () =>
                                _showParseSheet(catsAsync.value!),
                          )
                        : null,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                ),
                // B5 suggestion chip
                if (_isSuggesting)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white38),
                        ),
                        SizedBox(width: 6),
                        Text('Suggesting category…',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  )
                else if (_suggestedCategoryName != null)
                  _buildSuggestionChip(
                      _suggestedCategoryName!,
                      catsAsync.valueOrNull ?? []),
                const SizedBox(height: 16),

                // ── Category chips ────────────────────────────────────────
                const Text(
                  'CATEGORY',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                catsAsync.when(
                  data: (cats) => Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: cats
                        .where((c) => !c.isArchived)
                        .map((cat) {
                      final selected = _selectedCategoryId == cat.id;
                      return FilterChip(
                        label: Text(cat.name),
                        selected: selected,
                        onSelected: (_) => setState(() {
                          _selectedCategoryId = selected ? null : cat.id;
                        }),
                        avatar: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Color(cat.colorValue),
                            shape: BoxShape.circle,
                          ),
                        ),
                        selectedColor:
                            Color(cat.colorValue).withValues(alpha: 0.22),
                        checkmarkColor: Color(cat.colorValue),
                      );
                    }).toList(),
                  ),
                  loading: () => const SizedBox(
                    height: 32,
                    child:
                        Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),

                // ── Save ──────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors.accentForHour(_startTime.hour),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save entry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) => DateFormat('h:mm a').format(dt);

  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked == null || !mounted) return;

    final now = DateTime.now();
    final updated = DateTime(
        base.year, base.month, base.day, picked.hour, picked.minute);

    if (updated.isAfter(now)) {
      _showSnack('Cannot log future time.');
      return;
    }

    if (!isStart && !updated.isAfter(_startTime)) {
      _showSnack('End must be after start.');
      return;
    }

    setState(() {
      if (isStart) {
        _startTime = updated;
        if (!_endTime.isAfter(_startTime)) {
          final end = _startTime.add(const Duration(hours: 1));
          _endTime = end.isAfter(now) ? now : end;
        }
      } else {
        _endTime = updated;
      }
    });
  }

  Future<void> _save() async {
    if (!_endTime.isAfter(_startTime)) {
      _showSnack('End time must be after start time.');
      return;
    }
    setState(() => _isSaving = true);
    final db = ref.read(appDatabaseProvider);
    try {
      if (widget.existing != null) {
        await db.logEntriesDao.updateEntry(
          LogEntriesCompanion(
            id: Value(widget.existing!.id),
            description: Value(_descCtrl.text.trim()),
            categoryId: Value(_selectedCategoryId),
            startTime: Value(_startTime),
            endTime: Value(_endTime),
          ),
        );
      } else {
        // avoidUsageDerived: the log fills only the empty space, slotting
        // around any confirmed screen time rather than stacking on it.
        final result = await db.logEntriesDao.insertRetroactive(
          startTime: _startTime,
          endTime: _endTime,
          categoryId: _selectedCategoryId,
          description: _descCtrl.text.trim(),
          avoidUsageDerived: true,
        );
        // A partial fit is success — the log slotted in around the screen time.
        // Only a total block is worth stopping for, and then the sheet stays
        // open so the user doesn't lose what they typed.
        if (mounted && result.writtenMinutes == 0) {
          _showSnack(
              'That window is fully covered by screen time — nothing added.');
          return;
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _showSnack('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── B5: debounced category suggestion ──────────────────────────────────────

  void _onDescriptionChanged() {
    _debounceTimer?.cancel();
    final text = _descCtrl.text.trim();
    if (text.isEmpty) {
      if (_suggestedCategoryName != null) {
        setState(() => _suggestedCategoryName = null);
      }
      return;
    }
    _debounceTimer =
        Timer(const Duration(milliseconds: 600), _fetchCategorySuggestion);
  }

  Future<void> _fetchCategorySuggestion() async {
    final service = ref.read(aiServiceProvider);
    final cats = ref.read(categoriesProvider).valueOrNull ?? [];
    if (cats.isEmpty) return;
    if (mounted) setState(() => _isSuggesting = true);
    final suggestion = await service.suggestCategory(
      _descCtrl.text.trim(),
      cats.map((c) => c.name).toList(),
    );
    if (mounted) {
      setState(() {
        _suggestedCategoryName = suggestion;
        _isSuggesting = false;
      });
    }
  }

  Widget _buildSuggestionChip(String name, List<Category> cats) {
    final cat =
        cats.where((c) => c.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (cat == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedCategoryId = cat.id;
          _suggestedCategoryName = null;
        }),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: 12, color: Color(cat.colorValue)),
            const SizedBox(width: 5),
            Text(
              'Suggest: ${cat.name}  ↵ tap to apply',
              style: TextStyle(
                color: Color(cat.colorValue),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── B4: parse from free text ────────────────────────────────────────────────

  Future<void> _showParseSheet(List<Category> cats) async {
    final service = ref.read(aiServiceProvider);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ParseSheet(
        cats: cats,
        anchorTime: _startTime,
        service: service,
        onDone: () {
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}

// ── Missed-hours strip ────────────────────────────────────────────────────────

class _MissedHoursStrip extends StatelessWidget {
  final List<int> hours;
  final int selectedHour;
  final void Function(int) onTap;

  const _MissedHoursStrip({
    required this.hours,
    required this.selectedHour,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'UNLOGGED HOURS',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: hours.map((h) {
              final sel = h == selectedHour;
              final label = DateFormat('h a').format(DateTime(2000, 1, 1, h));
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  label: Text(label),
                  backgroundColor: sel
                      ? AppColors.accentForHour(h).withValues(alpha: 0.30)
                      : Colors.white.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: sel
                        ? AppColors.accentForHour(h).withValues(alpha: 0.60)
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                  labelStyle: TextStyle(
                    color: sel ? Colors.white : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                  onPressed: () => onTap(h),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── B4: Parse-from-text sheet ─────────────────────────────────────────────────

class _ParseSheet extends ConsumerStatefulWidget {
  final List<Category> cats;
  final DateTime anchorTime;
  final GroqService service;
  final VoidCallback onDone;

  const _ParseSheet({
    required this.cats,
    required this.anchorTime,
    required this.service,
    required this.onDone,
  });

  @override
  ConsumerState<_ParseSheet> createState() => _ParseSheetState();
}

class _ParseSheetState extends ConsumerState<_ParseSheet> {
  final _ctrl = TextEditingController();
  bool _isParsing = false;
  List<ParsedEntry>? _parsed;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _isParsing = true;
      _error = null;
      _parsed = null;
    });
    final catNames = widget.cats.map((c) => c.name).toList();
    final result = await widget.service
        .parseLogText(text, widget.anchorTime, catNames);
    if (mounted) {
      setState(() {
        _isParsing = false;
        if (result == null || result.isEmpty) {
          _error = 'Couldn\'t parse that — try being more specific.';
        } else {
          _parsed = result;
        }
      });
    }
  }

  Future<void> _confirm() async {
    if (_parsed == null) return;
    final db = ref.read(appDatabaseProvider);
    for (final e in _parsed!) {
      final catName = e.suggestedCategory?.toLowerCase();
      final cat = catName != null
          ? widget.cats
              .where((c) => c.name.toLowerCase() == catName)
              .firstOrNull
          : null;
      await db.logEntriesDao.insertRetroactive(
        startTime: e.startTime,
        endTime: e.endTime,
        categoryId: cat?.id,
        description: e.description,
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentForHour(DateTime.now().hour);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Parse from text',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Describe your day in plain language — AI will break it into entries.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (_parsed == null) ...[
              TextField(
                controller: _ctrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'e.g. "worked 2h, then lunch 30min, meeting 1h…"',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 12)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isParsing ? null : _parse,
                  icon: _isParsing
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(_isParsing ? 'Parsing…' : 'Parse with AI'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ] else ...[
              // Results list
              ...(_parsed!.map((e) {
                final catName = e.suggestedCategory;
                final cat = catName != null
                    ? widget.cats
                        .where((c) =>
                            c.name.toLowerCase() == catName.toLowerCase())
                        .firstOrNull
                    : null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Row(
                    children: [
                      if (cat != null)
                        Container(
                          width: 10, height: 10,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: Color(cat.colorValue),
                            shape: BoxShape.circle,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.description,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${DateFormat('HH:mm').format(e.startTime)}–'
                              '${DateFormat('HH:mm').format(e.endTime)}'
                              '${cat != null ? ' · ${cat.name}' : ''}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              })),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _parsed = null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Re-try'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Add ${_parsed!.length} '
                          '${_parsed!.length == 1 ? 'entry' : 'entries'}'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Sleep toggle row ─────────────────────────────────────────────────────────

class _SleepToggleRow extends ConsumerWidget {
  const _SleepToggleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final sleepActive = settings?.sleepModeActive ?? false;
    final startedAt = settings?.sleepModeStartedAt;

    final nightAccent = AppColors.accentForHour(2);
    final dayAccent = AppColors.accentForHour(DateTime.now().hour);

    final sublabel = sleepActive && startedAt != null
        ? 'Sleeping since ${DateFormat('h:mm a').format(startedAt)}'
        : 'Awake';

    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            sleepActive ? Icons.bedtime_rounded : Icons.wb_sunny_rounded,
            key: ValueKey(sleepActive),
            color: sleepActive ? nightAccent : dayAccent,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Align(
              key: ValueKey(sublabel),
              alignment: Alignment.centerLeft,
              child: Text(
                sublabel,
                style: TextStyle(
                  color: sleepActive ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight:
                      sleepActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        Switch(
          value: sleepActive,
          onChanged: (_) => ref
              .read(settingsNotifierProvider.notifier)
              .setSleepMode(active: !sleepActive),
          activeThumbColor: Colors.white,
          activeTrackColor: nightAccent,
          inactiveThumbColor: Colors.white54,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
        ),
      ],
    );
  }
}

// ── Time selector button ──────────────────────────────────────────────────────

class _TimeButton extends StatelessWidget {
  final String label;
  final DateTime time;
  final VoidCallback onTap;

  const _TimeButton({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      opacity: 0.08,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('HH:mm').format(time),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            DateFormat('MMM d').format(time),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
