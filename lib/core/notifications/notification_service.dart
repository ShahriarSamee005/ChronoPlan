import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'device_timezone.dart';
import 'notification_quotes.dart';
import 'quiet_hours.dart';

/// Overridden in main() with the pre-initialised instance.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

// ── Payload constants ──────────────────────────────────────────────────────
const kNotifPayloadLogEntry = 'open_log_entry';
const kNotifPayloadConfirmSleep = 'confirm_sleep';
const kNotifPayloadMorningIntention = 'morning_intention';
const kNotifPayloadWeeklyReflection = 'weekly_reflection';
const kNotifPayloadWakeUp = 'wake_up';

const _kChannelId = 'chronoplan_reminders';
const _kChannelName = 'Time Tracking Reminders';

// ── Reminder alarm ids ─────────────────────────────────────────────────────
// Hourly mode: one daily-repeating alarm per clock hour, id = base + hour.
const _kHourlyBaseId = 300; // 300..323
// Custom interval mode: one-shot alarms, id = base + slot index.
const _kIntervalBaseId = 100; // 100..147
const _kIntervalSlots = 48;

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  // Taps are broadcast so the app can react regardless of which screen is open
  final _tapController = StreamController<String>.broadcast();
  Stream<String> get tapStream => _tapController.stream;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init() async {
    tz.initializeTimeZones();
    // Must precede any scheduling: until this runs tz.local is UTC, and every
    // tz.TZDateTime(tz.local, ...) below would be built on a UTC wall clock.
    await initDeviceTimeZone();

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

  /// Whether the OS will actually deliver our notifications.
  ///
  /// On Android 13+ (targetSdk is 36) POST_NOTIFICATIONS starts denied, so
  /// this is false until the user grants it — and every alarm we schedule is
  /// dropped silently in the meantime. Also returns false when the user has
  /// switched notifications off in system settings after granting.
  ///
  /// Swallows platform failures and returns false, the same contract as
  /// `UsagePermissionChannel.isGranted()`: the channel is absent off Android
  /// and in headless tests, and neither is an error worth surfacing.
  Future<bool> isPermissionGranted() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Scheduling ────────────────────────────────────────────────────────────

  /// Hourly mode: fire once at the top of every hour (24 daily alarms), minus
  /// the ones that land in quiet hours — 16 alarms.
  Future<void> scheduleHourly() async {
    await cancelAll();
    await _armHourly();
  }

  /// Custom interval mode: fire every [intervalMinutes]. Lays 48 slots
  /// (≈ 2 days at 60 min) and skips any landing in quiet hours. The app
  /// reschedules on next open, so there is no gap.
  Future<void> scheduleCustomInterval({required int intervalMinutes}) async {
    await cancelAll();
    await _armCustomInterval(intervalMinutes);
  }

  /// Cancels every reminder alarm — hourly ids 300..323 and custom-interval
  /// ids 100..147 — and nothing else. The weekly reflection (998) and the
  /// inactivity check (999) stay armed, which is why the sleep toggle uses
  /// this rather than [cancelAll].
  ///
  /// Walks the full ranges rather than asking what is armed: cancelling an
  /// unscheduled id is a no-op, and quiet-hour gaps mean the armed set isn't
  /// contiguous anyway.
  Future<void> cancelReminders() async {
    for (var h = 0; h < 24; h++) {
      await _plugin.cancel(_kHourlyBaseId + h);
    }
    for (var i = 0; i < _kIntervalSlots; i++) {
      await _plugin.cancel(_kIntervalBaseId + i);
    }
  }

  /// Re-arms the reminders for [reminderMode] — the sleep-toggle-off path.
  ///
  /// Unlike [scheduleHourly] and [scheduleCustomInterval] this never calls
  /// [cancelAll]; it clears only the reminder ranges via [cancelReminders],
  /// so 998 and 999 survive. Quiet hours apply exactly as on resume.
  ///
  /// The mode rule mirrors the inline check in DashboardScreen._onResume:
  /// 'custom' and legacy 'strict' mean custom interval; anything else
  /// (including legacy 'gentle') means hourly.
  Future<void> rescheduleReminders({
    required String reminderMode,
    required int intervalMinutes,
  }) async {
    await cancelReminders();
    if (reminderMode == 'custom' || reminderMode == 'strict') {
      await _armCustomInterval(intervalMinutes);
    } else {
      await _armHourly();
    }
  }

  Future<void> _armHourly() async {
    final now = tz.TZDateTime.now(tz.local);
    for (var h = 0; h < 24; h++) {
      var fire = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, 0);
      if (fire.isBefore(now)) {
        // Rebuild on the next calendar day rather than adding 24h: across a
        // DST transition that would land on h±1:00. TZDateTime normalises the
        // overflowing day, so month/year ends need no special case.
        fire = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, h, 0);
      }
      if (firesInQuietHours(fire)) continue;
      await _scheduleOne(
        id: _kHourlyBaseId + h,
        fireAt: fire,
        matchComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> _armCustomInterval(int intervalMinutes) async {
    final now = tz.TZDateTime.now(tz.local);
    for (var i = 0; i < _kIntervalSlots; i++) {
      final fireAt = now.add(Duration(minutes: intervalMinutes * (i + 1)));
      // Skip, don't shift: the slot simply goes unfilled.
      if (firesInQuietHours(fireAt)) continue;
      await _scheduleOne(id: _kIntervalBaseId + i, fireAt: fireAt);
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

  // ── Wake notification ───────────────────────────────────────

  /// Its own id, clear of the reminder ranges (300..323, 100..147) and of the
  /// weekly reflection (998) and inactivity check (999).
  static const _kWakeId = 997;

  /// One light-hearted nudge [_kSleepAfter] after sleep mode began, pushed
  /// out of quiet hours by [wakeFireTime].
  ///
  /// Cancels its own id first, so toggling sleep on twice cannot leave two
  /// pending. Never touches any other id — in particular not 998 or 999.
  Future<void> scheduleWakeNotification({
    required DateTime sleepStartedAt,
  }) async {
    await _plugin.cancel(_kWakeId);
    await _plugin.zonedSchedule(
      _kWakeId,
      'Wakey wakey ☀️',
      'Your bed made a compelling argument. Tap to log the night.',
      wakeFireTime(sleepStartedAt),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: kNotifPayloadWakeUp,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Deliberately no matchDateTimeComponents: this fires once, not daily.
    );
  }

  Future<void> cancelWakeNotification() => _plugin.cancel(_kWakeId);

  // ── Weekly reflection (Sunday 8 PM) ──────────────────────────────────────

  static const _kWeeklyReflectionId = 998;

  /// Schedules a repeating Sunday 20:00 notification. Safe to call every
  /// resume — the existing alarm is replaced in-place.
  Future<void> scheduleWeeklyReflection() async {
    final now = tz.TZDateTime.now(tz.local);
    // Walk forward to the next Sunday, rebuilding each candidate so the hour
    // stays 20:00 on the wall clock even across a DST transition.
    var day = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0);
    var fire = day;
    for (var i = 0; fire.weekday != DateTime.sunday || fire.isBefore(now); i++) {
      day = tz.TZDateTime(tz.local, now.year, now.month, now.day + i + 1, 20, 0);
      fire = day;
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

/// When the wake nudge should actually fire for a sleep that began at
/// [sleepStartedAt]: eight hours later, or 09:00 that same local morning if
/// eight hours later lands inside quiet hours.
///
/// Quiet hours win absolutely, so this defers rather than skips — the nudge
/// is the only thing that ends sleep mode, and dropping it would strand the
/// user in it. Reuses [firesInQuietHours] and [kQuietEndHour] rather than
/// restating the window; the deferral target IS the end of the window.
tz.TZDateTime wakeFireTime(DateTime sleepStartedAt) {
  final target =
      tz.TZDateTime.from(sleepStartedAt, tz.local).add(_kSleepAfter);
  if (!firesInQuietHours(target)) return target;
  // Defer on the SAME clock the predicate judges on. firesInQuietHours reads
  // the DEVICE wall clock via the epoch, so 09:00 has to be found on the
  // device's calendar day - not on tz.local's, which differs whenever the
  // zone lookup fell back to UTC. Building it in tz.local instead can land
  // BEFORE now, and zonedSchedule rejects a past date, which would throw
  // straight out of setSleepMode and break the toggle.
  // NB: not target.toLocal() - the timezone package overrides toLocal() to
  // mean tz.local, not the device zone. Go through the epoch exactly as
  // firesInQuietHours does, so the two cannot disagree.
  final onDevice =
      DateTime.fromMillisecondsSinceEpoch(target.millisecondsSinceEpoch);
  final nine = DateTime(
      onDevice.year, onDevice.month, onDevice.day, kQuietEndHour);
  // Always strictly after target: the window is 01:00-08:59 device-local.
  return tz.TZDateTime.from(nine, tz.local);
}

const _kSleepAfter = Duration(hours: 8);

@pragma('vm:entry-point')
void _onBackgroundTap(NotificationResponse response) {
  // Background tap — navigation is deferred until the app foregrounds.
  // The payload is re-delivered via onDidReceiveNotificationResponse on resume.
  debugPrint('Background notification tapped: ${response.payload}');
}
