import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../core/usage_stats/usage_permission_channel.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/usage_stats_provider.dart';

/// Glassmorphic value-prop card explaining why the user should grant
/// Usage Access.  Visibility rules:
///   • Hidden once permission is granted (condition checked via provider)
///   • Hidden until appOpenCount >= 2 (not shown on very first session)
///   • Hidden permanently once the user taps ✕ (sets usageStatsPermissionAsked)
class UsageAccessCard extends ConsumerWidget {
  const UsageAccessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const SizedBox.shrink();
    if (settings.appOpenCount < 2) return const SizedBox.shrink();
    if (settings.usageStatsPermissionAsked) return const SizedBox.shrink();

    final granted = ref.watch(usagePermissionProvider).valueOrNull ?? false;
    if (granted) return const SizedBox.shrink();

    final accent = AppColors.accentForHour(DateTime.now().hour);

    return GlassCard(
      opacity: 0.12,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Enable Screen Time Tracking',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => ref
                    .read(settingsNotifierProvider.notifier)
                    .dismissUsageStatsCard(),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white38, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Grant Usage Access to auto-suggest log entries from your '
            'real phone usage and cross-check planned time against '
            'actual screen time.',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: UsagePermissionChannel.openSettings,
              icon: const Icon(Icons.settings_rounded, size: 16),
              label: const Text('Enable Screen Time'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
