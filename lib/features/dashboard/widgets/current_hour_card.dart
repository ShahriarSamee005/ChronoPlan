import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/log_entries_provider.dart';

class CurrentHourCard extends ConsumerWidget {
  const CurrentHourCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayEntriesProvider);
    final catsAsync = ref.watch(categoriesProvider);
    final tt = Theme.of(context).textTheme;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date + live clock
          Row(
            children: [
              Text(
                DateFormat('EEEE, MMM d')
                    .format(DateTime.now())
                    .toUpperCase(),
                style: tt.labelSmall,
              ),
              const Spacer(),
              const _LiveClock(),
            ],
          ),
          const SizedBox(height: 14),
          Text('Right now', style: tt.labelSmall),
          const SizedBox(height: 6),

          // Current activity — built from two async sources
          todayAsync.when(
            data: (entries) {
              final now = DateTime.now();
              final current = entries
                  .where(
                    (e) =>
                        e.startTime.isBefore(now) &&
                        e.endTime.isAfter(now),
                  )
                  .firstOrNull;

              if (current == null) {
                return Text(
                  '— nothing logged',
                  style: tt.titleLarge?.copyWith(
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }

              // Extract categoryId here so it's captured by value,
              // not as a field access across the catsAsync closure.
              final categoryId = current.categoryId;

              return catsAsync.when(
                data: (cats) {
                  final cat = categoryId == null
                      ? null
                      : cats
                          .where((c) => c.id == categoryId)
                          .firstOrNull;

                  return Row(
                    children: [
                      if (cat != null) ...[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Color(cat.colorValue),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          current.description.isNotEmpty
                              ? current.description
                              : (cat?.name ?? 'Logged'),
                          style: tt.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
            loading: () => const LinearProgressIndicator(
              backgroundColor: Colors.transparent,
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ── Live clock widget ────────────────────────────────────────────────────────

class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late String _time;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Align the first tick to the next minute boundary, then tick each minute.
    final now = DateTime.now();
    final delay = Duration(
      seconds: 60 - now.second,
      milliseconds: -now.millisecond,
    );
    Future.delayed(delay, _startTicking);
  }

  void _startTicking() {
    if (!mounted) return;
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  void _refresh() {
    if (mounted) {
      setState(() => _time = DateFormat('HH:mm').format(DateTime.now()));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _time,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
    );
  }
}
