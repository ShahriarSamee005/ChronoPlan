import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/notification_service.dart';

/// Whether the OS will actually deliver our notifications.  Invalidated on
/// every app resume — and again right after the enable button runs — so a
/// grant made in the system dialog or the settings page is reflected without
/// a full restart.  Mirrors `usagePermissionProvider`.
final notificationPermissionProvider = FutureProvider<bool>((ref) {
  return ref.watch(notificationServiceProvider).isPermissionGranted();
});
