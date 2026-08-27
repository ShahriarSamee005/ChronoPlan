import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/log_entries_provider.dart';
import '../../providers/routine_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';
import '../log_entry/log_entry_sheet.dart';
import 'hour_row_planner.dart';
import 'routine_overlay_planner.dart';

/// Height of one lane inside an hour row. Tall enough that a 15-minute block
/// still has room for its label.
const double _laneHeight = 52.0;

/// Floor width for very short slivers so they stay tappable. A 15-minute block
/// sits well above this at its true width, so the layout stays truthful.
const double _minSegWidth = 48.0;

const double _gutterWidth = 52.0;

class DayViewScreen extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  const DayViewScreen({super.key, this.initialDate});

  @override
  ConsumerState<DayViewScreen> createState() => _DayViewScreenState();
}

class _DayViewScreenState extends ConsumerState<DayViewScreen> {
  late DateTime _date;
  final _scrollCtrl = ScrollController();
  final Set<int> _pendingDeleteIds = {};

  /// Drives the now-line and the current-hour row once a minute.
  Timer? _ticker;

  /// The initial jump-to-now is one-shot; later scrolls are the user's.
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  void _prevDay() =>
      setState(() => _date = _date.subtract(const Duration(days: 1)));

  void _nextDay() {
    final candidate = _date.add(const Duration(days: 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!candidate.isAfter(today)) setState(() => _date = candidate);
  }

  /// Rows vary in height, so the landing offset is the running sum of the hours
  /// above the target rather than a flat `hour * hourPx`.
  void _scheduleInitialScroll(List<List<HourSegment>> rows) {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    final target = (DateTime.now().hour - 2).clamp(0, 23);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      var offset = 0.0;
      for (var h = 0; h < target; h++) {
        offset += _rowHeight(rows, h);
      }
      final max = _scrollCtrl.position.maxScrollExtent;
      _scrollCtrl.jumpTo(offset > max ? max : offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(dayViewEntriesProvider(_date));
    final catsAsync = ref.watch(categoriesProvider);
    final routineAsync = ref.watch(allRoutineSlotsProvider);

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
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => context.pop(),
              )
            : null,
        title: _DateNav(
          date: _date,
          onPrev: _prevDay,
          onNext: _nextDay,
          canGoNext: !_isToday,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: Colors.white),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: entriesAsync.when(
            data: (entries) {
              _pendingDeleteIds
                  .removeWhere((id) => !entries.any((e) => e.id == id));
              final visible = entries
                  .where((e) => !_pendingDeleteIds.contains(e.id))
                  .toList();
              final rows = planHourRows(
                visible
                    .map((e) => (
                          entryId: e.id,
                          start: e.startTime,
                          end: e.endTime,
                        ))
                    .toList(),
                day: _date,
              );
              _scheduleInitialScroll(rows);

              // Compute routine overlay for the day.
              final routineEdges = routineAsync.whenData((allSlots) {
                // Filter to applicable slots: isActive + applicable day-of-week.
                final daySlots = allSlots
                    .where((s) =>
                        s.isActive &&
                        (s.dayOfWeek == _date.weekday || s.dayOfWeek == 0))
                    .map((s) => (
                          startHour: s.startHour,
                          durationHours: s.durationHours,
                          categoryId: s.categoryId,
                        ))
                    .toList();

                final planLogs = visible
                    .map((e) => (
                          start: e.startTime,
                          end: e.endTime,
                          categoryId: e.categoryId,
                        ))
                    .toList();

                return planRoutineEdges(
                  daySlots,
                  planLogs,
                  day: _date,
                  now: DateTime.now(),
                );
              }).valueOrNull;

              return _Timeline(
                rows: rows,
                byId: {for (final e in visible) e.id: e},
                cats: catsAsync.valueOrNull ?? [],
                routineEdges: routineEdges,
                isToday: _isToday,
                scrollCtrl: _scrollCtrl,
                onEntryTap: (entry) => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useRootNavigator: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => LogEntrySheet(existing: entry),
                ),
                onDeleteEntry: (entry) {
                  // Keyed on the ENTRY, not the segment, so every slice of a
                  // multi-hour block disappears in the same frame.
                  setState(() => _pendingDeleteIds.add(entry.id));
                  ref
                      .read(appDatabaseProvider)
                      .logEntriesDao
                      .deleteEntry(entry.id);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('$e', style: const TextStyle(color: Colors.white54)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The planner guarantees one uniform `laneCount` across an hour's segments.
int _laneCountOf(List<List<HourSegment>> rows, int hour) =>
    rows[hour].isEmpty ? 1 : rows[hour].first.laneCount;

double _rowHeight(List<List<HourSegment>> rows, int hour) =>
    _laneHeight * _laneCountOf(rows, hour);

// ── Date navigation row ──────────────────────────────────────────────────────

class _DateNav extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool canGoNext;

  const _DateNav({
    required this.date,
    required this.onPrev,
    required this.onNext,
    required this.canGoNext,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final label = isToday ? 'Today' : DateFormat('EEE, MMM d').format(date);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          onPressed: onPrev,
          padding: EdgeInsets.zero,
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right_rounded,
            color: canGoNext ? Colors.white : Colors.white30,
          ),
          onPressed: canGoNext ? onNext : null,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

// ── 24-hour timeline, one row per hour ───────────────────────────────────────

class _Timeline extends StatelessWidget {
  final List<List<HourSegment>> rows;
  final Map<int, LogEntry> byId;
  final List<Category> cats;
  final List<HourRoutine?>? routineEdges;
  final bool isToday;
  final ScrollController scrollCtrl;
  final void Function(LogEntry) onEntryTap;
  final void Function(LogEntry) onDeleteEntry;

  const _Timeline({
    required this.rows,
    required this.byId,
    required this.cats,
    required this.routineEdges,
    required this.isToday,
    required this.scrollCtrl,
    required this.onEntryTap,
    required this.onDeleteEntry,
  });

  @override
  Widget build(BuildContext context) {
    // Built once, not per segment — a day can hold hundreds of slices.
    final byCatId = {for (final c in cats) c.id: c};
    final now = DateTime.now();

    return ListView.builder(
      controller: scrollCtrl,
      // Rows vary in height with their lane count, so no itemExtent.
      itemCount: 24,
      padding: const EdgeInsets.only(bottom: 100),
      itemBuilder: (_, h) => _HourRow(
        hour: h,
        segments: rows[h],
        height: _rowHeight(rows, h),
        byId: byId,
        byCatId: byCatId,
        routineEdge: routineEdges?[h],
        isToday: isToday,
        now: now,
        onEntryTap: onEntryTap,
        onDeleteEntry: onDeleteEntry,
      ),
    );
  }
}

class _HourRow extends StatelessWidget {
  final int hour;
  final List<HourSegment> segments;
  final double height;
  final Map<int, LogEntry> byId;
  final Map<int, Category> byCatId;
  final HourRoutine? routineEdge;
  final bool isToday;
  final DateTime now;
  final void Function(LogEntry) onEntryTap;
  final void Function(LogEntry) onDeleteEntry;

  const _HourRow({
    required this.hour,
    required this.segments,
    required this.height,
    required this.byId,
    required this.byCatId,
    required this.routineEdge,
    required this.isToday,
    required this.now,
    required this.onEntryTap,
    required this.onDeleteEntry,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrentHour = isToday && now.hour == hour;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _gutterWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 6, top: 2),
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Hour divider, painted inside the Stack so it costs no
                    // layout height (the scroll offset math depends on that).
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 0.5,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    // Routine overlay edge (behind segments).
                    if (routineEdge != null)
                      IgnorePointer(
                        child: _routineEdge(
                          routineEdge!,
                          height,
                          byCatId[routineEdge!.categoryId]?.colorValue ?? 0xFF607D8B,
                        ),
                      ),
                    for (final seg in segments) ..._segment(seg, w),
                    if (isCurrentHour) ..._nowLine(constraints.maxHeight),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _routineEdge(HourRoutine routine, double height, int colorValue) {
    final color = Color(colorValue);

    // Determine edge color and width based on verdict.
    final (edgeColor, edgeWidth) = _verdictToEdge(routine.verdict, color);

    return Positioned(
      top: 0,
      left: 2,
      right: 2,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: edgeColor, width: edgeWidth),
            top: BorderSide(color: color.withValues(alpha: 0.14), width: 0.5),
            right: BorderSide(color: color.withValues(alpha: 0.14), width: 0.5),
            bottom: BorderSide(color: color.withValues(alpha: 0.14), width: 0.5),
          ),
        ),
      ),
    );
  }

  (Color, double) _verdictToEdge(RoutineVerdict verdict, Color categoryColor) {
    switch (verdict) {
      case RoutineVerdict.green:
        return (Colors.greenAccent, 3.5);
      case RoutineVerdict.amber:
        return (Colors.amberAccent, 3.5);
      case RoutineVerdict.red:
        return (Colors.redAccent.withValues(alpha: 0.7), 3.5);
      case RoutineVerdict.neutral:
        return (categoryColor.withValues(alpha: 0.22), 1.5);
    }
  }

  List<Widget> _segment(HourSegment seg, double w) {
    final entry = byId[seg.entryId];
    if (entry == null) return const [];

    final color = Color(byCatId[entry.categoryId]?.colorValue ?? 0xFF607D8B);

    var left = seg.startMin / 60 * w;
    var width = (seg.endMin - seg.startMin) / 60 * w;
    if (width < _minSegWidth) width = _minSegWidth;
    if (width > w) width = w;
    // A floored sliver near the right edge would overflow — shift it back in.
    if (left + width > w) left = w - width;
    if (left < 0) left = 0;

    // Round only the outer ends so a multi-hour entry reads as one bar.
    const r = Radius.circular(8);
    final radius = BorderRadius.only(
      topLeft: seg.isFirstOfEntry ? r : Radius.zero,
      bottomLeft: seg.isFirstOfEntry ? r : Radius.zero,
      topRight: seg.isLastOfEntry ? r : Radius.zero,
      bottomRight: seg.isLastOfEntry ? r : Radius.zero,
    );

    return [
      Positioned(
        left: left,
        top: seg.lane * _laneHeight,
        width: width,
        // 4 px breathing room between stacked lanes.
        height: _laneHeight - 4,
        child: Dismissible(
          key: ValueKey('seg_${seg.entryId}_${hour}_${seg.lane}'),
          direction:
              isToday ? DismissDirection.endToStart : DismissDirection.none,
          resizeDuration: null,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.20),
              borderRadius: radius,
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 18),
          ),
          onDismissed: (_) => onDeleteEntry(entry),
          child: ClipRRect(
            // GlassCard only takes a uniform double radius, so the per-corner
            // shape has to come from the clip.
            borderRadius: radius,
            // GlassCard's own detector is opaque and innermost, so the tap has
            // to be registered there — an outer GestureDetector never sees it.
            child: GlassCard(
              onTap: () => onEntryTap(entry),
              // Without an explicit size the card shrinks to its label, so the
              // bar would render as a chip and only the text would be tappable.
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
              opacity: 0.13,
              blurSigma: 6,
              fillColor: color.withValues(alpha: 0.22),
              borderColor: color.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: seg.isFirstOfEntry
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (entry.description.isNotEmpty)
                          Flexible(
                            child: Text(
                              entry.description,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (entry.isRealTime)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'LIVE',
                              style: TextStyle(
                                color: color,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                      ],
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ];
  }

  /// Slides down through the current hour's row as the minutes pass, then jumps
  /// to the top of the next row on the hour. Drawn last so it rides above the
  /// blocks it crosses.
  List<Widget> _nowLine(double h) {
    var y = now.minute / 60 * h;
    if (y > h - 1.5) y = h - 1.5;
    if (y < 0) y = 0;
    return [
      Positioned(
        key: const Key('now_line'),
        left: 0,
        right: 0,
        top: y,
        height: 1.5,
        child: const IgnorePointer(
          child: ColoredBox(color: Colors.redAccent),
        ),
      ),
      Positioned(
        left: 0,
        top: y - 2.75,
        child: const IgnorePointer(
          child: SizedBox(
            width: 7,
            height: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
