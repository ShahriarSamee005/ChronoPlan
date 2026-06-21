import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/log_entries_provider.dart';

class DailyPieChartCard extends ConsumerWidget {
  const DailyPieChartCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayEntriesProvider);
    final catsAsync = ref.watch(categoriesProvider);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: todayAsync.when(
        data: (entries) => catsAsync.when(
          data: (cats) => _ChartBody(entries: entries, cats: cats),
          loading: () => const _EmptyState(),
          error: (_, __) => const _EmptyState(),
        ),
        loading: () => const _EmptyState(),
        error: (_, __) => const _EmptyState(),
      ),
    );
  }
}

// ── Chart body ───────────────────────────────────────────────────────────────

class _ChartBody extends StatefulWidget {
  final List<dynamic> entries; // LogEntry after generation
  final List<dynamic> cats; // Category after generation

  const _ChartBody({required this.entries, required this.cats});

  @override
  State<_ChartBody> createState() => _ChartBodyState();
}

class _ChartBodyState extends State<_ChartBody> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final data = _buildData();

    if (data.isEmpty) return const _EmptyState();

    final totalMin =
        data.fold(0, (sum, item) => sum + item.dur.inMinutes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "TODAY'S BREAKDOWN",
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 190,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: PieChart(
                  PieChartData(
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        setState(() {
                          _touchedIndex = response
                                  ?.touchedSection
                                  ?.touchedSectionIndex ??
                              -1;
                        });
                      },
                    ),
                    sections: _buildSections(data, totalMin),
                    centerSpaceRadius: 34,
                    sectionsSpace: 2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _Legend(data: data, totalMin: totalMin),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildSections(
    List<({dynamic cat, Duration dur})> data,
    int totalMin,
  ) {
    return List.generate(data.length, (i) {
      final item = data[i];
      final isTouched = i == _touchedIndex;
      final pct = item.dur.inMinutes / totalMin * 100;
      return PieChartSectionData(
        value: item.dur.inMinutes.toDouble(),
        color: Color(item.cat.colorValue as int)
            .withValues(alpha: isTouched ? 1.0 : 0.82),
        radius: isTouched ? 82 : 70,
        title: isTouched ? '${pct.round()}%' : '',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      );
    });
  }

  /// Groups entries by category and sorts by duration descending.
  List<({dynamic cat, Duration dur})> _buildData() {
    final byId = <int, Duration>{};
    for (final e in widget.entries) {
      final catId = e.categoryId as int?;
      if (catId == null) continue;
      final dur = (e.endTime as DateTime)
          .difference(e.startTime as DateTime);
      byId[catId] = (byId[catId] ?? Duration.zero) + dur;
    }

    final result = <({dynamic cat, Duration dur})>[];
    for (final entry in byId.entries) {
      final cat = widget.cats
          .where((c) => (c.id as int) == entry.key)
          .firstOrNull;
      if (cat != null) result.add((cat: cat, dur: entry.value));
    }
    result.sort((a, b) => b.dur.compareTo(a.dur));
    return result;
  }
}

// ── Legend ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final List<({dynamic cat, Duration dur})> data;
  final int totalMin;

  const _Legend({required this.data, required this.totalMin});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: data.map((item) {
        final h = item.dur.inHours;
        final m = item.dur.inMinutes % 60;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Color(item.cat.colorValue as int),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.cat.name as String,
                  style: tt.bodyMedium?.copyWith(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                h > 0
                    ? '${h}h${m > 0 ? '${m}m' : ''}'
                    : '${m}m',
                style: tt.labelSmall?.copyWith(fontSize: 10),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "TODAY'S BREAKDOWN",
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 48),
        Center(
          child: Text(
            'Start logging to see your day unfold.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
