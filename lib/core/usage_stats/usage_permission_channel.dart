import 'dart:io';

import 'package:flutter/services.dart';

/// Thin Dart wrapper around the single-purpose method channel that lives in
/// MainActivity.kt.  Only two operations are exposed:
///   1. Check whether Usage Access is currently granted.
///   2. Open the system Usage Access settings screen.
///
/// Usage data itself does NOT flow through this channel — that comes from
/// the app_usage package directly.
class UsagePermissionChannel {
  static const _ch =
      MethodChannel('com.example.chronoplan/usage_permission');

  /// Returns true if the user has granted Usage Access on Android.
  /// Always returns false on non-Android platforms.
  static Future<bool> isGranted() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('isUsageAccessGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launches Settings.ACTION_USAGE_ACCESS_SETTINGS via an Android intent.
  /// No-op on non-Android platforms.
  static Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<void>('openUsageAccessSettings');
    } catch (_) {}
  }
}
