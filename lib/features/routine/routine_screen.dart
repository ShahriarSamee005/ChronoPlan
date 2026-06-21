import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/routine_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';

class RoutineScreen extends ConsumerStatefulWidget {
  const RoutineScreen({super.key});

  @override
  ConsumerState<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends ConsumerState<RoutineScreen> {
  late int _selectedDay;
  static const _hourPx = 72.0;
  final _scrollCtrl = ScrollController();

  static const _days = [
    (1, 'Mon'), (2, 'Tue'), (3, 'Wed'), (4, 'Thu'),
    (5, 'Fri'), (6, 'Sat'), (7, 'Sun'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now().weekday.clamp(1, 7);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCtrl.animateTo(
        6 * _hourPx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
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
                    final cats = catsAsync.valueOrNull ?? [];
                    final daySlots = all
                        .where((s) =>
                            s.dayOfWeek == _selectedDay ||
                            s.dayOfWeek == 0)
                        .toList();
                    return _RoutineTimeline(
                      slots: daySlots,
                      cats: cats,
                      hourPx: _hourPx,
                      scrollCtrl: _scrollCtrl,
                      onTapHour: (h) => _openSheet(startHour: h),
                      onTapSlot: (slot) => _openSheet(existing: slot),
                      onDeleteSlot: (id) => ref
                          .read(appDatabaseProvider)
                          .routineSlotsDao
                          .deleteSlot(id),
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

// ── 24-hour routine timeline ──────────────────────────────────────────────────

class _RoutineTimeline extends StatelessWidget {
  final List<RoutineSlot> slots;
  final List<Category> cats;
  final double hourPx;
  final ScrollController scrollCtrl;
  final void Function(int hour) onTapHour;
  final void Function(RoutineSlot) onTapSlot;
  final void Function(int id) onDeleteSlot;

  const _RoutineTimeline({
    required this.slots,
    required this.cats,
    required this.hourPx,
    required this.scrollCtrl,
    required this.onTapHour,
    required this.onTapSlot,
    required this.onDeleteSlot,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollCtrl,
      padding: const EdgeInsets.only(bottom: 100),
      child: SizedBox(
        height: hourPx * 24 + 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hour labels
            SizedBox(
              width: 52,
              child: Stack(
                children: List.generate(25, (h) => Positioned(
                  top: h * hourPx - 6,
                  left: 0,
                  right: 4,
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )),
              ),
            ),
            // Timeline body
            Expanded(
              child: Stack(
                children: [
                  // Tappable empty cells (behind slot blocks)
                  ...List.generate(24, (h) {
                    final covered = slots.any((s) =>
                        h >= s.startHour &&
                        h < s.startHour + s.durationHours);
                    return Positioned(
                      top: h * hourPx,
                      left: 0,
                      right: 0,
                      height: hourPx,
                      child: covered
                          ? const SizedBox.expand()
                          : GestureDetector(
                              onTap: () => onTapHour(h),
                              behavior: HitTestBehavior.opaque,
                              child: Container(color: Colors.transparent),
                            ),
                    );
                  }),
                  // Hour dividers
                  ...List.generate(24, (h) => Positioned(
                    top: h * hourPx,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 0.5,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  )),
                  // Slot blocks
                  ...slots.map((slot) => _slotBlock(slot)),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _slotBlock(RoutineSlot slot) {
    final top = slot.startHour * hourPx + 1;
    final height = (slot.durationHours * hourPx - 2).clamp(6.0, double.infinity);
    final cat = cats.where((c) => c.id == slot.categoryId).firstOrNull;
    final color = Color(cat?.colorValue ?? 0xFF607D8B);
    final isEveryDay = slot.dayOfWeek == 0;

    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height,
      child: Dismissible(
        key: ValueKey('rslot_${slot.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent, size: 18),
        ),
        onDismissed: (_) => onDeleteSlot(slot.id),
        child: GlassCard(
          borderRadius: 8,
          opacity: isEveryDay ? 0.06 : 0.12,
          blurSigma: 5,
          fillColor: color.withValues(alpha: isEveryDay ? 0.12 : 0.25),
          borderColor: color.withValues(alpha: isEveryDay ? 0.30 : 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          onTap: () => onTapSlot(slot),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  slot.label.isNotEmpty
                      ? slot.label
                      : (cat?.name ?? 'Unlabelled'),
                  style: TextStyle(
                    color: isEveryDay ? Colors.white70 : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isEveryDay && height > 28)
                Text(
                  'Every day',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.70),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
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
