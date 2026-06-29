import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';
import '../dashboard/widgets/weekly_insight_card.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

DateTime _thisSunday() {
  final now = DateTime.now();
  // weekday: Mon=1 … Sun=7.  weekday % 7 gives days since last Sunday.
  final sunday = now.subtract(Duration(days: now.weekday % 7));
  return DateTime(sunday.year, sunday.month, sunday.day);
}

String _fmtHours(double h) {
  final totalMin = (h * 60).round().abs();
  final hh = totalMin ~/ 60;
  final mm = totalMin % 60;
  if (hh == 0) return '${mm}m';
  if (mm == 0) return '${hh}h';
  return '${hh}h ${mm}m';
}

bool _isToday(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _selectedWeekStartProvider =
    StateProvider<DateTime>((ref) => _thisSunday());

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
    final prevEntriesAsync = ref.watch(
        _weekEntriesProvider(weekStart.subtract(const Duration(days: 7))));
    final catsAsync = ref.watch(categoriesProvider);

    final isCurrentWeek = weekStart == _thisSunday();

    void goWeek(int deltaDays) => ref
        .read(_selectedWeekStartProvider.notifier)
        .state = weekStart.add(Duration(days: deltaDays));

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
              _WeekNav(
                weekStart: weekStart,
                isCurrentWeek: isCurrentWeek,
                onPrev: () => goWeek(-7),
                onNext: isCurrentWeek ? null : () => goWeek(7),
              ),
              Expanded(
                child: entriesAsync.when(
                  data: (entries) => _WeekBody(
                    weekStart: weekStart,
                    entries: entries,
                    prevEntries: prevEntriesAsync.valueOrNull,
                    cats: catsAsync.valueOrNull ?? [],
                    isCurrentWeek: isCurrentWeek,
                    onDayTap: (date) =>
                        context.push('/day-view', extra: date),
                  ),
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
    final range = '${DateFormat('MMM d').format(weekStart)} – '
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
          Column(
            children: [
              Text(
                range,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              if (isCurrentWeek)
                const Text(
                  'This week',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
            ],
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

// ── Body: trend + chart + day rows + insight ──────────────────────────────────

class _WeekBody extends StatelessWidget {
  final DateTime weekStart;
  final List<LogEntry> entries;
  final List<LogEntry>? prevEntries; // null = still loading
  final List<Category> cats;
  final bool isCurrentWeek;
  final void Function(DateTime) onDayTap;

  const _WeekBody({
    required this.weekStart,
    required this.entries,
    required this.prevEntries,
    required this.cats,
    required this.isCurrentWeek,
    required this.onDayTap,
  });

  // dayIndex → {catId → hours}, Sunday=0 … Saturday=6
  Map<int, Map<int?, double>> _buildDayData() {
    final dayData = <int, Map<int?, double>>{};
    for (final e in entries) {
      final dayIdx = e.startTime.difference(weekStart).inDays.clamp(0, 6);
      final catId = e.categoryId;
      final hours = e.endTime.difference(e.startTime).inMinutes / 60.0;
      dayData[dayIdx] ??= {};
      dayData[dayIdx]![catId] = (dayData[dayIdx]![catId] ?? 0) + hours;
    }
    return dayData;
  }

  @override
  Widget build(BuildContext context) {
    final dayData = _buildDayData();
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        // ── Trend summary ──────────────────────────────────────────────
        _TrendRow(entries: entries, prevEntries: prevEntries, cats: cats),
        const SizedBox(height: 12),

        // ── Stacked bar chart or empty message ────────────────────────
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.bar_chart_rounded,
                    color: Colors.white24, size: 56),
                SizedBox(height: 14),
                Text(
                  'No entries this week',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Log some time to see your weekly breakdown.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          )
        else ...[
          _BarChartCard(
            weekStart: weekStart,
            dayData: dayData,
            cats: cats,
            onDayTap: onDayTap,
          ),
          const SizedBox(height: 16),
          // Day rows
          ...List.generate(7, (i) => _DayRow(
                date: days[i],
                catMap: dayData[i] ?? {},
                cats: cats,
                onTap: () => onDayTap(days[i]),
              )),
        ],

        const SizedBox(height: 8),
        // ── Weekly AI insight (current week only) ─────────────────────
        if (isCurrentWeek) const WeeklyInsightCard(),
      ],
    );
  }
}

// ── Trend summary row ─────────────────────────────────────────────────────────

class _TrendRow extends StatelessWidget {
  final List<LogEntry> entries;
  final List<LogEntry>? prevEntries;
  final List<Category> cats;

  const _TrendRow({
    required this.entries,
    required this.prevEntries,
    required this.cats,
  });

  @override
  Widget build(BuildContext context) {
    final totalMin = entries.fold(
        0, (s, e) => s + e.endTime.difference(e.startTime).inMinutes);
    final prevMin = (prevEntries ?? []).fold(
        0, (s, e) => s + e.endTime.difference(e.startTime).inMinutes);

    // Top category by minutes
    final catMin = <int?, int>{};
    for (final e in entries) {
      catMin[e.categoryId] = (catMin[e.categoryId] ?? 0) +
          e.endTime.difference(e.startTime).inMinutes;
    }
    final topEntry = catMin.isEmpty
        ? null
        : catMin.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final topCat = topEntry != null
        ? cats.where((c) => c.id == topEntry.key).firstOrNull
        : null;

    final deltaMin = totalMin - prevMin;
    final prevLoaded = prevEntries != null;
    final noDelta = !prevLoaded || (totalMin == 0 && prevMin == 0);

    return GlassCard(
      opacity: 0.10,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          _Stat(
            label: 'Total',
            child: Text(
              _fmtHours(totalMin / 60.0),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _vDivider(),
          _Stat(
            label: 'Top Category',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (topCat != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color(topCat.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    topCat?.name ?? (entries.isEmpty ? '–' : 'None'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _vDivider(),
          _Stat(
            label: 'vs Last Week',
            child: noDelta
                ? const Text(
                    '–',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        deltaMin >= 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 12,
                        color: deltaMin >= 0
                            ? const Color(0xFF6BCB77)
                            : const Color(0xFFFF6B6B),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _fmtHours(deltaMin.abs() / 60.0),
                        style: TextStyle(
                          color: deltaMin >= 0
                              ? const Color(0xFF6BCB77)
                              : const Color(0xFFFF6B6B),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 0.5,
        height: 36,
        color: Colors.white12,
        margin: const EdgeInsets.symmetric(horizontal: 6),
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final Widget child;

  const _Stat({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

// ── Stacked bar chart ─────────────────────────────────────────────────────────

class _BarChartCard extends StatelessWidget {
  final DateTime weekStart;
  final Map<int, Map<int?, double>> dayData;
  final List<Category> cats;
  final void Function(DateTime) onDayTap;

  const _BarChartCard({
    required this.weekStart,
    required this.dayData,
    required this.cats,
    required this.onDayTap,
  });

  Color _catColor(int? id) => Color(
      cats.where((c) => c.id == id).firstOrNull?.colorValue ?? 0xFF607D8B);

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentForHour(DateTime.now().hour);

    final barGroups = List.generate(7, (dayIdx) {
      final catMap = dayData[dayIdx] ?? {};
      double cumY = 0;
      final rods = <BarChartRodStackItem>[];
      for (final kv in catMap.entries) {
        rods.add(BarChartRodStackItem(cumY, cumY + kv.value, _catColor(kv.key)));
        cumY += kv.value;
      }
      // Empty-day slot: invisible stub so the bar is present but blank
      if (rods.isEmpty) {
        rods.add(BarChartRodStackItem(0, 0.01, Colors.white10));
        cumY = 0.01;
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

    final maxY = barGroups
        .map((g) => g.barRods.first.toY)
        .fold(0.0, (a, b) => a > b ? a : b);

    const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return GlassCard(
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
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 9),
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
                    final i = v.round().clamp(0, 6);
                    final date = weekStart.add(Duration(days: i));
                    final today = _isToday(date);
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        dayLabels[i],
                        style: TextStyle(
                          color: today ? accent : Colors.white54,
                          fontSize: 10,
                          fontWeight:
                              today ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => Colors.transparent,
                getTooltipItem: (_, __, ___, ____) => null,
              ),
              touchCallback: (event, response) {
                if (event is FlTapUpEvent && response?.spot != null) {
                  final dayIdx = response!.spot!.touchedBarGroupIndex;
                  onDayTap(weekStart.add(Duration(days: dayIdx)));
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Day summary row ───────────────────────────────────────────────────────────

class _DayRow extends StatelessWidget {
  final DateTime date;
  final Map<int?, double> catMap;
  final List<Category> cats;
  final VoidCallback onTap;

  const _DayRow({
    required this.date,
    required this.catMap,
    required this.cats,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalH = catMap.values.fold(0.0, (a, b) => a + b);
    final today = _isToday(date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        opacity: today ? 0.15 : 0.08,
        onTap: totalH > 0 ? onTap : null,
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
                      color: today
                          ? AppColors.accentForHour(DateTime.now().hour)
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    DateFormat('d').format(date),
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: totalH > 0
                  ? _CategoryBar(catMap: catMap, cats: cats, totalH: totalH)
                  : const Text(
                      'No entries',
                      style:
                          TextStyle(color: Colors.white24, fontSize: 12),
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              totalH > 0 ? _fmtHours(totalH) : '',
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
  }
}

// ── Inline category proportion bar ────────────────────────────────────────────

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
              flex: (e.value * 100 / totalH).round().clamp(1, 100),
              child: Container(color: color),
            );
          }).toList(),
        ),
      ),
    );
  }
}
