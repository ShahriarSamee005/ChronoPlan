import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/routine_provider.dart';
import '../current_slot_planner.dart';

class CurrentHourCard extends ConsumerStatefulWidget {
  const CurrentHourCard({super.key});

  @override
  ConsumerState<CurrentHourCard> createState() => _CurrentHourCardState();
}

class _CurrentHourCardState extends ConsumerState<CurrentHourCard> {
  // Rebuilds the routine strip when the clock rolls into a new hour. Separate
  // from _LiveClock's timer on purpose: _LiveClock rebuilds itself every minute
  // for the HH:mm string, while this only rebuilds the card body — and only on
  // an hour change. One timer can't serve both without folding _LiveClock into
  // this widget, which would change its per-minute behaviour.
  Timer? _timer;
  late int _lastHour;

  @override
  void initState() {
    super.initState();
    _lastHour = DateTime.now().hour;
    // Align the first tick to the next minute boundary, then tick each minute —
    // same pattern as _LiveClock.
    final now = DateTime.now();
    final delay = Duration(
      seconds: 60 - now.second,
      milliseconds: -now.millisecond,
    );
    Future.delayed(delay, _startTicking);
  }

  void _startTicking() {
    if (!mounted) return;
    _checkHour();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkHour());
  }

  void _checkHour() {
    if (!mounted) return;
    final hour = DateTime.now().hour;
    if (hour != _lastHour) {
      setState(() => _lastHour = hour);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slotsAsync = ref.watch(allRoutineSlotsProvider);
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

          // What the ROUTINE says should be happening this hour.
          slotsAsync.when(
            data: (slots) {
              final planned = slotForHour(
                slots
                    .map((s) => (
                          id: s.id,
                          startHour: s.startHour,
                          durationHours: s.durationHours,
                          dayOfWeek: s.dayOfWeek,
                          isActive: s.isActive,
                          label: s.label,
                          categoryId: s.categoryId,
                        ))
                    .toList(),
                now: DateTime.now(),
              );

              if (planned == null) {
                return Text(
                  '— nothing planned',
                  style: tt.titleLarge?.copyWith(
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }

              // Capture by value so the catsAsync closure doesn't reach back
              // across the planned record.
              final categoryId = planned.categoryId;
              final slotLabel = planned.label;

              return catsAsync.when(
                data: (cats) {
                  final cat = categoryId == null
                      ? null
                      : cats
                          .where((c) => c.id == categoryId)
                          .firstOrNull;
                  final name = resolveSlotName(slotLabel, cat?.name);

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
                          name,
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
