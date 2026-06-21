import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'notification_quotes.dart';

/// Overridden in main() with the pre-initialised instance.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

// ── Payload constants ──────────────────────────────────────────────────────
const kNotifPayloadLogEntry = 'open_log_entry';
const kNotifPayloadConfirmSleep = 'confirm_sleep';
const kNotifPayloadMorningIntention = 'morning_intention';
const kNotifPayloadWeeklyReflection = 'weekly_reflection';

const _kChannelId = 'chronoplan_reminders';
const _kChannelName = 'Time Tracking Reminders';

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  // Taps are broadcast so the app can react regardless of which screen is open
  final _tapController = StreamController<String>.broadcast();
  Stream<String> get tapStream => _tapController.stream;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init() async {
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundTap,
    );

    await _createChannel();
  }

  Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: 'Contextual prompts to log your time.',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _onTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _tapController.add(payload);
    }
  }

  // ── Permissions ───────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  // ── Scheduling ────────────────────────────────────────────────────────────

  /// Hourly mode: fire once at the top of every hour (24 daily alarms).
  Future<void> scheduleHourly() async {
    await cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    for (var h = 0; h < 24; h++) {
      var fire = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, 0);
      if (fire.isBefore(now)) fire = fire.add(const Duration(days: 1));
      await _scheduleOne(
        id: 300 + h,
        fireAt: fire,
        matchComponents: DateTimeComponents.time,
      );
    }
  }

  /// Custom interval mode: fire every [intervalMinutes]. Schedules 48 alarms
  /// (≈ 2 days). The app reschedules on next open, so there is no gap.
  Future<void> scheduleCustomInterval({required int intervalMinutes}) async {
    await cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    for (var i = 0; i < 48; i++) {
      final fireAt = now.add(Duration(minutes: intervalMinutes * (i + 1)));
      await _scheduleOne(id: 100 + i, fireAt: fireAt);
    }
  }

  Future<void> _scheduleOne({
    required int id,
    required tz.TZDateTime fireAt,
    DateTimeComponents? matchComponents,
  }) async {
    final hour = fireAt.hour;
    final quote = NotificationQuotes.quoteForHour(hour);

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: 'Contextual prompts to log your time.',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(quote),
        ticker: 'Time to log',
      ),
    );

    await _plugin.zonedSchedule(
      id,
      'Time to log ✦',
      quote,
      fireAt,
      details,
      payload: kNotifPayloadLogEntry,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: matchComponents,
    );
  }

  // ── Inactivity / auto-sleep detection ────────────────────────────────────

  static const _kInactivityId = 999;

  /// Schedule a "still sleeping?" nudge 7 hours from now.
  /// Call on every app-pause; cancelled on next resume.
  Future<void> scheduleInactivityCheck() async {
    await _plugin.cancel(_kInactivityId);
    final fireAt =
        tz.TZDateTime.now(tz.local).add(const Duration(hours: 7));
    await _plugin.zonedSchedule(
      _kInactivityId,
      'Still sleeping? 🌙',
      'Tap when you\'re up — your sleep will be logged automatically.',
      fireAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: kNotifPayloadConfirmSleep,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelInactivityCheck() => _plugin.cancel(_kInactivityId);

  // ── One-off notifications ─────────────────────────────────────────────────

  /// Shown next morning when auto-sleep was detected.
  Future<void> showSleepConfirmation() async {
    await _plugin.show(
      1,
      'Good morning! 🌅',
      'Did you sleep? Tap to confirm and set your sleep window.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: kNotifPayloadConfirmSleep,
    );
  }

  /// Morning intention prompt.
  Future<void> showIntentionPrompt() async {
    await _plugin.show(
      2,
      "What's the one thing that would make today a win?",
      'Set your daily intention.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: kNotifPayloadMorningIntention,
    );
  }

  // ── Weekly reflection (Sunday 8 PM) ──────────────────────────────────────

  static const _kWeeklyReflectionId = 998;

  /// Schedules a repeating Sunday 20:00 notification. Safe to call every
  /// resume — the existing alarm is replaced in-place.
  Future<void> scheduleWeeklyReflection() async {
    final now = tz.TZDateTime.now(tz.local);
    var fire = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0);
    // Walk forward to the next Sunday
    while (fire.weekday != DateTime.sunday || fire.isBefore(now)) {
      fire = fire.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      _kWeeklyReflectionId,
      'How was your week? ✨',
      'Reflect with your AI coach and set up next week.',
      fire,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: kNotifPayloadWeeklyReflection,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  void dispose() => _tapController.close();
}

@pragma('vm:entry-point')
void _onBackgroundTap(NotificationResponse response) {
  // Background tap — navigation is deferred until the app foregrounds.
  // The payload is re-delivered via onDidReceiveNotificationResponse on resume.
  debugPrint('Background notification tapped: ${response.payload}');
}
