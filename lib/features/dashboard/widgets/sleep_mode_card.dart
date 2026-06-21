import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/settings_provider.dart';

class SleepModeCard extends ConsumerWidget {
  const SleepModeCard({super.key});

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

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          // ── Animated sun ↔ moon icon ───────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              sleepActive ? Icons.bedtime_rounded : Icons.wb_sunny_rounded,
              key: ValueKey(sleepActive),
              color: sleepActive ? nightAccent : dayAccent,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          // ── Label ─────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sleep mode',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Align(
                    key: ValueKey(sublabel),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      sublabel,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Switch ───────────────────────────────────────────────────
          Switch(
            value: sleepActive,
            onChanged: (_) => ref
                .read(settingsNotifierProvider.notifier)
                .setSleepMode(active: !sleepActive),
            activeThumbColor: Colors.white,
            activeTrackColor: nightAccent,
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
          ),
        ],
      ),
    );
  }
}
