import 'dart:io';

import 'package:flutter/services.dart';

/// Thin Dart wrapper around the single-purpose method channel that lives in
/// MainActivity.kt.  Only one operation is exposed:
///   1. Open the app's own system notification settings screen.
///
/// This is the escape hatch for the POST_NOTIFICATIONS ask limit: Android
/// stops showing the runtime dialog after two denials, and from then on
/// `requestNotificationsPermission()` returns false without showing anything.
/// The settings page is the only remaining way for the user to say yes.
///
/// Checking whether the permission is held does NOT flow through this channel
/// — that comes from `NotificationService.isPermissionGranted()`, which asks
/// flutter_local_notifications directly.
class NotificationPermissionChannel {
  static const _ch =
      MethodChannel('com.example.chronoplan/notification_permission');

  /// Launches Settings.ACTION_APP_NOTIFICATION_SETTINGS via an Android intent
  /// (falling back to the app details page below API 26, see MainActivity).
  /// No-op on non-Android platforms.
  static Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<void>('openNotificationSettings');
    } catch (_) {}
  }
}
