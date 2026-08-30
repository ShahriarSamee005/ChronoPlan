import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/hour_timeline.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/log_entries_provider.dart';
import '../../providers/routine_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';
import '../log_entry/log_entry_sheet.dart';
import 'hour_row_planner.dart';
import 'routine_overlay_planner.dart';

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
        offset += HourTimeline.rowHeight(rows, h);
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

              // Look-up maps and snapshots for the shared timeline's callbacks
              // and per-row layer builders.
              final byId = {for (final e in visible) e.id: e};
              final cats = catsAsync.valueOrNull ?? <Category>[];
              final byCatId = {for (final c in cats) c.id: c};
              final now = DateTime.now();
              final isToday = _isToday;

              return HourTimeline(
                rows: rows,
                scrollController: _scrollCtrl,
                segmentColor: (id) => Color(
                    byCatId[byId[id]?.categoryId]?.colorValue ?? 0xFF607D8B),
                segmentLabel: (id) => byId[id]?.description ?? '',
                onSegmentTap: (id) {
                  final entry = byId[id];
                  if (entry == null) return;
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useRootNavigator: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => LogEntrySheet(existing: entry),
                  );
                },
                onSegmentDelete: (id) {
                  // Keyed on the ENTRY, not the segment, so every slice of a
                  // multi-hour block disappears in the same frame.
                  setState(() => _pendingDeleteIds.add(id));
                  ref.read(appDatabaseProvider).logEntriesDao.deleteEntry(id);
                },
                swipeEnabled: isToday,
                onEmptyHourTap: null,
                backgroundLayers: (hour, w, rowH) {
                  final edge = routineEdges?[hour];
                  if (edge == null) return const <Widget>[];
                  final colorValue =
                      byCatId[edge.categoryId]?.colorValue ?? 0xFF607D8B;
                  return [_routineEdge(edge, hour, rowH, colorValue)];
                },
                foregroundLayers: (hour, w, rowH) {
                  if (!(isToday && now.hour == hour)) return const <Widget>[];
                  return _nowLine(rowH, now);
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

// ── Day-View-specific per-row layers ─────────────────────────────────────────
//
// These are the layers that vary per screen: the routine overlay edge (a
// background layer) and the now-line (a foreground layer). They are handed to
// the shared [HourTimeline] through its background/foreground layer builders.

/// Routine overlay edge (behind segments). Reads the hour's [HourRoutine] and
/// draws a rounded faint base block plus a verdict-coloured accent bar.
Widget _routineEdge(
    HourRoutine routine, int hour, double height, int colorValue) {
  final color = Color(colorValue);

  // Determine edge color and width based on verdict.
  final (edgeColor, edgeWidth) = _verdictToEdge(routine.verdict, color);

  return Positioned(
    top: 0,
    left: 2,
    right: 2,
    height: height,
    child: IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Rounded base block: uniform faint border + radius (legal to paint).
          Container(
            key: ValueKey('routine_edge_$hour'),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: color.withValues(alpha: 0.14),
                width: 0.5,
              ),
            ),
          ),
          // Verdict-coloured accent bar, layered on the left edge.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              key: ValueKey('routine_accent_$hour'),
              width: edgeWidth,
              decoration: BoxDecoration(
                color: edgeColor,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(6)),
              ),
            ),
          ),
        ],
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

/// Slides down through the current hour's row as the minutes pass, then jumps
/// to the top of the next row on the hour. Drawn last so it rides above the
/// blocks it crosses.
List<Widget> _nowLine(double h, DateTime now) {
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
