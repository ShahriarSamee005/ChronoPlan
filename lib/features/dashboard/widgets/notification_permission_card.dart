import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_permission_channel.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/notification_permission_provider.dart';
import '../../../providers/settings_provider.dart';

/// Glassmorphic value-prop card asking for POST_NOTIFICATIONS.  Without it
/// every alarm the app schedules is dropped silently by the OS on Android 13+,
/// so the hourly reminder loop — the app's core loop — never runs.
///
/// Visibility rules:
///   • Hidden until appOpenCount >= 2 (not shown on very first session),
///     the same rule the usage-access card uses
///   • Hidden once permission is granted (condition checked via provider)
///
/// Deliberately NOT dismissible: unlike Usage Access, which enhances the app,
/// notifications are what the app *is*.  There is no ✕ and no dismissal flag.
///
/// Renders its own 12px bottom gap so it can sit in the Dashboard's ListView
/// without a paired SizedBox that would leave a hole when the card hides.
class NotificationPermissionCard extends ConsumerStatefulWidget {
  const NotificationPermissionCard({super.key});

  @override
  ConsumerState<NotificationPermissionCard> createState() =>
      _NotificationPermissionCardState();
}

class _NotificationPermissionCardState
    extends ConsumerState<NotificationPermissionCard> {
  bool _busy = false;

  /// Android shows the POST_NOTIFICATIONS dialog at most twice; after the
  /// second denial `requestNotificationsPermission()` returns false without
  /// showing anything, and a button that only called it would silently do
  /// nothing forever.  flutter_local_notifications exposes no
  /// shouldShowRequestPermissionRationale equivalent, so the two states can't
  /// be told apart up front — instead we ask, and if the ask neither granted
  /// the permission nor (evidently) showed a dialog, fall through to the
  /// settings page on the same tap.
  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(notificationServiceProvider);
      final granted = await service.requestPermission();
      if (!granted && !await service.isPermissionGranted()) {
        await NotificationPermissionChannel.openSettings();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // Resume also invalidates this, but the runtime dialog does not always
        // produce a lifecycle round-trip — so refresh here too and let the
        // card hide the moment permission lands.
        ref.invalidate(notificationPermissionProvider);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const SizedBox.shrink();
    if (settings.appOpenCount < 2) return const SizedBox.shrink();

    final granted =
        ref.watch(notificationPermissionProvider).valueOrNull ?? false;
    if (granted) return const SizedBox.shrink();

    final accent = AppColors.accentForHour(DateTime.now().hour);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        opacity: 0.12,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_off_rounded, color: accent, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Turn On Reminders',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'ChronoPlan nudges you as each hour ends so you can log what you '
              'actually did with it. Without notification permission those '
              'reminders never arrive.',
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
                onPressed: _busy ? null : _enable,
                icon: const Icon(Icons.notifications_active_rounded, size: 16),
                label: const Text('Enable Reminders'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
