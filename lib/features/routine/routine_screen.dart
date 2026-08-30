import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../core/theme/hour_timeline.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/routine_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';
import '../day_view/hour_row_planner.dart';
import 'routine_plan_adapter.dart';

class RoutineScreen extends ConsumerStatefulWidget {
  const RoutineScreen({super.key});

  @override
  ConsumerState<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends ConsumerState<RoutineScreen> {
  late int _selectedDay;
  final _scrollCtrl = ScrollController();

  /// Optimistic-delete guard: a swiped slot is hidden here immediately so the
  /// dismissed `Dismissible` leaves the tree before the async Drift delete lands
  /// (otherwise the "dismissed Dismissible still in the tree" assertion fires).
  /// Self-prunes when the stream re-emits without the id. Mirrors Day View.
  final Set<int> _pendingDeleteIds = {};

  /// A routine template has no "now", so there is no scroll-to-now. The one-shot
  /// initial scroll just lands near the morning (hour 06:00), as before.
  bool _didInitialScroll = false;

  static const _days = [
    (1, 'Mon'), (2, 'Tue'), (3, 'Wed'), (4, 'Thu'),
    (5, 'Fri'), (6, 'Sat'), (7, 'Sun'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now().weekday.clamp(1, 7);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Rows vary in height with their lane count, so the landing offset is the
  /// running sum of the hours above 06:00 rather than a flat `hour * hourPx`.
  void _scheduleInitialScroll(List<List<HourSegment>> rows) {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      var offset = 0.0;
      for (var h = 0; h < 6; h++) {
        offset += HourTimeline.rowHeight(rows, h);
      }
      final max = _scrollCtrl.position.maxScrollExtent;
      _scrollCtrl.animateTo(
        offset > max ? max : offset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final slotsAsync = ref.watch(allRoutineSlotsProvider);
    final catsAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white),
                onPressed: () => context.pop(),
              )
            : null,
        title: const Text(
          'Routine',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_rounded, color: Colors.white),
            tooltip: 'Copy day to…',
            onPressed: () =>
                _showCopyDialog(slotsAsync.valueOrNull ?? []),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline_rounded,
                color: Colors.white),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── Day pills ─────────────────────────────────────────────
              _DayPills(
                days: _days,
                selected: _selectedDay,
                onSelect: (d) => setState(() => _selectedDay = d),
              ),
              // ── Timeline ──────────────────────────────────────────────
              Expanded(
                child: slotsAsync.when(
                  data: (all) {
                    // Drop ids that already vanished from the stream, then apply
                    // the (unchanged) dayOfWeek-only filter plus the optimistic
                    // delete guard.
                    _pendingDeleteIds
                        .removeWhere((id) => !all.any((s) => s.id == id));
                    final cats = catsAsync.valueOrNull ?? <Category>[];
                    final byCatId = {for (final c in cats) c.id: c};
                    final daySlots = all
                        .where((s) =>
                            (s.dayOfWeek == _selectedDay ||
                                s.dayOfWeek == 0) &&
                            !_pendingDeleteIds.contains(s.id))
                        .toList();

                    // A routine template is weekday-keyed, not date-keyed; any
                    // consistent day anchors the hour math and the midnight clip.
                    final now = DateTime.now();
                    final day = DateTime(now.year, now.month, now.day);
                    final rows = planHourRows(
                      slotsToPlanEntries(
                        daySlots
                            .map((s) => (
                                  id: s.id,
                                  startHour: s.startHour,
                                  durationHours: s.durationHours,
                                ))
                            .toList(),
                        day: day,
                      ),
                      day: day,
                    );
                    _scheduleInitialScroll(rows);

                    final byId = {for (final s in daySlots) s.id: s};

                    return HourTimeline(
                      rows: rows,
                      scrollController: _scrollCtrl,
                      segmentColor: (id) => Color(
                          byCatId[byId[id]?.categoryId]?.colorValue ??
                              0xFF607D8B),
                      segmentLabel: (id) {
                        final slot = byId[id];
                        if (slot == null) return '';
                        final cat = byCatId[slot.categoryId];
                        return slot.label.isNotEmpty
                            ? slot.label
                            : (cat?.name ?? 'Unlabelled');
                      },
                      onSegmentTap: (id) {
                        final slot = byId[id];
                        if (slot != null) _openSheet(existing: slot);
                      },
                      onSegmentDelete: (id) {
                        setState(() => _pendingDeleteIds.add(id));
                        ref
                            .read(appDatabaseProvider)
                            .routineSlotsDao
                            .deleteSlot(id);
                      },
                      swipeEnabled: true,
                      onEmptyHourTap: (h) => _openSheet(startHour: h),
                      backgroundLayers: null,
                      foregroundLayers: null,
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('$e',
                        style: const TextStyle(color: Colors.white54)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet({int? startHour, RoutineSlot? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SlotSheet(
        existing: existing,
        dayOfWeek: _selectedDay,
        startHour: startHour ?? existing?.startHour ?? 8,
      ),
    );
  }

  Future<void> _showCopyDialog(List<RoutineSlot> all) async {
    final sourceSlots =
        all.where((s) => s.dayOfWeek == _selectedDay).toList();
    if (sourceSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No slots on this day to copy.')),
      );
      return;
    }

    final selected = <int>{};
    final dayName =
        _days.firstWhere((d) => d.$1 == _selectedDay).$2;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1A1040),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Copy $dayName to…',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _days
                .where((d) => d.$1 != _selectedDay)
                .map((d) => CheckboxListTile(
                      value: selected.contains(d.$1),
                      onChanged: (v) => setS(() =>
                          v! ? selected.add(d.$1) : selected.remove(d.$1)),
                      title: Text(d.$2,
                          style: const TextStyle(color: Colors.white)),
                      controlAffinity: ListTileControlAffinity.leading,
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected.isEmpty
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      await ref
                          .read(appDatabaseProvider)
                          .routineSlotsDao
                          .copyDaySlots(
                              _selectedDay, selected.toList());
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Copied to ${selected.length} day(s).')),
                        );
                      }
                    },
              child: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Day pills ─────────────────────────────────────────────────────────────────

class _DayPills extends StatelessWidget {
  final List<(int, String)> days;
  final int selected;
  final void Function(int) onSelect;

  const _DayPills({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentForHour(DateTime.now().hour);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: days.map((d) {
          final (val, label) = d;
          final sel = val == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(label),
              backgroundColor: sel
                  ? accent.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.07),
              side: BorderSide(
                color: sel
                    ? accent.withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.15),
              ),
              labelStyle: TextStyle(
                color: sel ? Colors.white : AppColors.textMuted,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
              onPressed: () => onSelect(val),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Add / edit slot bottom sheet ──────────────────────────────────────────────

class _SlotSheet extends ConsumerStatefulWidget {
  final RoutineSlot? existing;
  final int dayOfWeek;
  final int startHour;

  const _SlotSheet({
    this.existing,
    required this.dayOfWeek,
    required this.startHour,
  });

  @override
  ConsumerState<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends ConsumerState<_SlotSheet> {
  final _labelCtrl = TextEditingController();
  int? _categoryId;
  late int _durationHours;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _labelCtrl.text = e.label;
      _categoryId = e.categoryId;
      _durationHours = e.durationHours;
    } else {
      _durationHours = 1;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(categoriesProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: GlassCard(
        borderRadius: 28,
        opacity: 0.18,
        blurSigma: 16,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
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
                Text(
                  widget.existing != null ? 'Edit slot' : 'New slot',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.startHour.toString().padLeft(2, '0')}:00 – '
                  '${(widget.startHour + _durationHours).toString().padLeft(2, '0')}:00',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                // Label
                TextField(
                  controller: _labelCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Label (optional)'),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                // Duration
                _sectionLabel('DURATION'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [1, 2, 3, 4].map((h) => FilterChip(
                    label: Text('${h}h'),
                    selected: _durationHours == h,
                    onSelected: (_) =>
                        setState(() => _durationHours = h),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                // Category
                _sectionLabel('CATEGORY'),
                const SizedBox(height: 8),
                catsAsync.when(
                  data: (cats) => Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: cats
                        .where((c) => !c.isArchived)
                        .map((cat) {
                      final sel = _categoryId == cat.id;
                      return FilterChip(
                        label: Text(cat.name),
                        selected: sel,
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
                        onSelected: (_) => setState(
                            () => _categoryId = sel ? null : cat.id),
                      );
                    }).toList(),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors.accentForHour(DateTime.now().hour),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Save slot'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    final dao = ref.read(appDatabaseProvider).routineSlotsDao;
    final companion = RoutineSlotsCompanion(
      id: widget.existing != null
          ? Value(widget.existing!.id)
          : const Value.absent(),
      label: Value(_labelCtrl.text.trim()),
      categoryId: Value(_categoryId),
      dayOfWeek: Value(widget.dayOfWeek),
      startHour: Value(widget.startHour),
      durationHours: Value(_durationHours),
      isActive: const Value(true),
    );
    try {
      if (widget.existing != null) {
        await dao.updateSlot(companion);
      } else {
        await dao.insertSlot(companion);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
