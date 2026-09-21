import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/settings_provider.dart';

/// Dashboard card shown only while sleep mode is on, so the state is visible
/// without opening the log sheet to check.  Tapping it opens that sheet, where
/// the sun/moon toggle is the first thing above the fold.
///
/// Visibility rules:
///   • Hidden until the settings row has loaded
///   • Hidden whenever sleepModeActive is false
///
/// [onTap] is injected rather than opening the sheet here: DashboardScreen
/// already owns `_openLogSheet()` and the BuildContext it needs, and a second
/// copy of that showModalBottomSheet chrome would only drift from the first.
///
/// Renders its own 12px bottom gap so it can sit in the Dashboard's ListView
/// without a paired SizedBox that would leave a hole when the card hides.
class SleepActiveCard extends ConsumerWidget {
  final VoidCallback onTap;

  const SleepActiveCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const SizedBox.shrink();
    if (!settings.sleepModeActive) return const SizedBox.shrink();

    // setSleepMode always writes sleepModeActive and sleepModeStartedAt in the
    // same patch, so this should never be null here — but the column IS
    // nullable, and "Since null" is worse than one line.
    final startedAt = settings.sleepModeStartedAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        onTap: onTap,
        child: Row(
          children: [
            // The night accent, matching how sleep state reads elsewhere.
            Icon(
              Icons.bedtime_rounded,
              color: AppColors.accentForHour(2),
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Sleep mode is on',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (startedAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Since ${DateFormat('h:mm a').format(startedAt)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
