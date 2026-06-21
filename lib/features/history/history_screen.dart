import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';

// ── Week provider ─────────────────────────────────────────────────────────────

final _selectedWeekStartProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  // Most recent Monday
  final monday = now.subtract(Duration(days: now.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
});

final _weekEntriesProvider =
    FutureProvider.family<List<LogEntry>, DateTime>((ref, weekStart) {
  return ref.watch(appDatabaseProvider).logEntriesDao.getForWeek(weekStart);
});

// ── Screen ────────────────────────────────────────────────────────────────────

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(_selectedWeekStartProvider);
    final entriesAsync = ref.watch(_weekEntriesProvider(weekStart));
    final catsAsync = ref.watch(categoriesProvider);

    final now = DateTime.now();
    final thisMonday = now.subtract(Duration(days: now.weekday - 1));
    final isCurrentWeek = weekStart.year == thisMonday.year &&
        weekStart.month == thisMonday.month &&
        weekStart.day == thisMonday.day;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: GestureDetector(
          onTap: () => context.push('/about'),
          child: const Text(
            'ChronoPlan',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 0.3,
            ),
          ),
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
          child: Column(
            children: [
              // Week navigator
              _WeekNav(
                weekStart: weekStart,
                isCurrentWeek: isCurrentWeek,
                onPrev: () => ref
                    .read(_selectedWeekStartProvider.notifier)
                    .state = weekStart.subtract(const Duration(days: 7)),
                onNext: isCurrentWeek
                    ? null
                    : () => ref
                        .read(_selectedWeekStartProvider.notifier)
                        .state = weekStart.add(const Duration(days: 7)),
              ),
              Expanded(
                child: entriesAsync.when(
                  data: (entries) => _WeekView(
                    weekStart: weekStart,
                    entries: entries,
                    cats: catsAsync.valueOrNull ?? [],
                    onDayTap: (date) => context.push(
                      '/day-view',
                      extra: date,
                    ),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('$e',
                        style:
                            const TextStyle(color: Colors.white54)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Week navigation row ───────────────────────────────────────────────────────

class _WeekNav extends StatelessWidget {
  final DateTime weekStart;
  final bool isCurrentWeek;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _WeekNav({
    required this.weekStart,
    required this.isCurrentWeek,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final label = isCurrentWeek
        ? 'This week'
        : '${DateFormat('MMM d').format(weekStart)} – '
            '${DateFormat('MMM d').format(weekEnd)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
            onPressed: onPrev,
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.chevron_right_rounded,
              color: onNext != null ? Colors.white : Colors.white30,
            ),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// ── Week view with bar chart ──────────────────────────────────────────────────

class _WeekView extends StatelessWidget {
  final DateTime weekStart;
  final List<LogEntry> entries;
  final List<Category> cats;
  final void Function(DateTime) onDayTap;

  const _WeekView({
    required this.weekStart,
    required this.entries,
    required this.cats,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    // Group entries by day and category
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final dayData = <int, Map<int?, double>>{}; // dayIndex → {catId → hours}

    for (final e in entries) {
      final dayIdx = e.startTime.difference(weekStart).inDays.clamp(0, 6);
      final catId = e.categoryId;
      final hours = e.endTime.difference(e.startTime).inMinutes / 60.0;
      dayData[dayIdx] ??= {};
      dayData[dayIdx]![catId] = (dayData[dayIdx]![catId] ?? 0) + hours;
    }

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded,
                color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            const Text(
              'No entries this week',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    // Build bar groups
    final barGroups = List.generate(7, (dayIdx) {
      final catMap = dayData[dayIdx] ?? {};
      double cumY = 0;
      final rods = <BarChartRodStackItem>[];
      for (final entry in catMap.entries) {
        final color = Color(
            cats.where((c) => c.id == entry.key).firstOrNull?.colorValue ??
                0xFF607D8B);
        rods.add(BarChartRodStackItem(cumY, cumY + entry.value, color));
        cumY += entry.value;
      }
      return BarChartGroupData(
        x: dayIdx,
        barRods: [
          BarChartRodData(
            toY: cumY,
            width: 28,
            rodStackItems: rods,
            borderRadius: BorderRadius.circular(6),
            color: Colors.transparent,
          ),
        ],
      );
    });

    final maxY =
        barGroups.map((g) => g.barRods.first.toY).fold(0.0, (a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        GlassCard(
          opacity: 0.10,
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
          child: SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: (maxY + 2).ceilToDouble(),
                barGroups: barGroups,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.08),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text(
                        '${v.round()}h',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 9),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        const labels = [
                          'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
                        ];
                        final i = v.round();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            labels[i],
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchCallback: (event, response) {
                    if (event is FlTapUpEvent &&
                        response?.spot != null) {
                      final dayIdx = response!.spot!.touchedBarGroupIndex;
                      onDayTap(weekStart.add(Duration(days: dayIdx)));
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Day rows
        ...List.generate(7, (i) {
          final date = days[i];
          final catMap = dayData[i] ?? {};
          final totalH = catMap.values.fold(0.0, (a, b) => a + b);
          final isToday = _isToday(date);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              opacity: isToday ? 0.15 : 0.08,
              onTap: totalH > 0 ? () => onDayTap(date) : null,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEE').format(date),
                          style: TextStyle(
                            color: isToday
                                ? AppColors.accentForHour(
                                    DateTime.now().hour)
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          DateFormat('d').format(date),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: totalH > 0
                        ? _CategoryBar(
                            catMap: catMap,
                            cats: cats,
                            totalH: totalH,
                          )
                        : const Text(
                            'No entries',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 12),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    totalH > 0
                        ? '${totalH.round()}h'
                        : '',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

// ── Inline category bar ───────────────────────────────────────────────────────

class _CategoryBar extends StatelessWidget {
  final Map<int?, double> catMap;
  final List<Category> cats;
  final double totalH;

  const _CategoryBar(
      {required this.catMap, required this.cats, required this.totalH});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: catMap.entries.map((e) {
            final color = Color(
                cats.where((c) => c.id == e.key).firstOrNull?.colorValue ??
                    0xFF607D8B);
            return Expanded(
              flex: (e.value * 100 / totalH).round(),
              child: Container(color: color),
            );
          }).toList(),
        ),
      ),
    );
  }
}
