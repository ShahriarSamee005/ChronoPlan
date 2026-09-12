import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/notifications/notification_service.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/settings_provider.dart';

/// Same channel-level fake as reminder_scheduling_test: record what would
/// reach Android, not what Dart was asked to do.
class _AlarmTable {
  final armed = <int, Map<Object?, Object?>>{};
  int cancelAllCalls = 0;
  /// Per-id call counts. `armed` is keyed by id, so a re-schedule of the same
  /// id is invisible there - these are what let a test see the calls
  /// themselves rather than just the resulting state.
  final scheduleCalls = <int, int>{};
  final cancelCalls = <int, int>{};

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'zonedSchedule':
        final m = args as Map<Object?, Object?>;
        final id = m['id']! as int;
        armed[id] = m;
        scheduleCalls[id] = (scheduleCalls[id] ?? 0) + 1;
      case 'cancel':
        final id = (args as Map<Object?, Object?>)['id']! as int;
        armed.remove(id);
        cancelCalls[id] = (cancelCalls[id] ?? 0) + 1;
      case 'cancelAll':
        cancelAllCalls++;
        armed.clear();
      case 'initialize':
        return true;
    }
    return null;
  }

  Set<int> get ids => armed.keys.toSet();
  DateTime instantOf(int id) =>
      DateTime.parse(armed[id]!['scheduledDateTimeISO8601']! as String);
}

const _wakeId = 997;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late _AlarmTable alarms;

  // A fixed zone, so "22:00 local" means one thing wherever the suite runs.
  late tz.Location dhaka;

  setUpAll(() {
    tzdata.initializeTimeZones();
    dhaka = tz.getLocation('Asia/Dhaka');
  });

  setUp(() {
    tz.setLocalLocation(dhaka);
    alarms = _AlarmTable();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, alarms.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    tz.setLocalLocation(tz.UTC);
  });

  /// The armed wake alarm, read back on the local clock.
  tz.TZDateTime firedAt() =>
      tz.TZDateTime.from(alarms.instantOf(_wakeId), dhaka);

  /// A local calendar day safely ahead of now. The plugin rejects a
  /// scheduledDate in the past, so the fixtures below are anchored forward
  /// rather than to a hard-coded date that rots the moment it passes.
  late tz.TZDateTime day0;

  setUp(() {
    final soon = tz.TZDateTime.now(dhaka).add(const Duration(days: 2));
    day0 = tz.TZDateTime(dhaka, soon.year, soon.month, soon.day);
  });

  /// [h]:[m] local, [dayOffset] days after [day0].
  tz.TZDateTime at(int dayOffset, int h, [int m = 0]) =>
      tz.TZDateTime(dhaka, day0.year, day0.month, day0.day + dayOffset, h, m);

  // -- Quiet-hour deferral ---------------------------------------------------

  group('when it fires', () {
    test('toggle on at 22:00 -> 8h is 06:00, quiet, so deferred to 09:00',
        () async {
      await NotificationService()
          .scheduleWakeNotification(sleepStartedAt: at(0, 22));

      final fired = firedAt();
      expect(fired.hour, 9,
          reason: '06:00 is inside 01:00-08:59, defer to 09:00');
      expect(fired.minute, 0);
      expect(fired, at(1, 9), reason: 'the same morning the 8h mark landed on');
    });

    test('toggle on at 14:00 -> 8h is 22:00, not quiet, not deferred',
        () async {
      await NotificationService()
          .scheduleWakeNotification(sleepStartedAt: at(0, 14));

      expect(firedAt(), at(0, 22));
    });

    test('toggle on at 02:00 -> 8h is 10:00, outside quiet hours, not deferred',
        () async {
      await NotificationService()
          .scheduleWakeNotification(sleepStartedAt: at(0, 2));

      expect(firedAt(), at(0, 10));
    });

    test('boundaries: an 8h mark at 00:59 is left alone, at 01:00 it defers',
        () async {
      final service = NotificationService();

      await service.scheduleWakeNotification(sleepStartedAt: at(0, 16, 59));
      expect(firedAt(), at(1, 0, 59));

      await service.scheduleWakeNotification(sleepStartedAt: at(0, 17));
      expect(firedAt(), at(1, 9));
    });

    test('every quiet landing defers to 09:00 that same morning', () async {
      final service = NotificationService();
      for (var h = 1; h <= 8; h++) {
        final target = at(1, h);
        await service.scheduleWakeNotification(
            sleepStartedAt: target.subtract(const Duration(hours: 8)));
        expect(firedAt(), at(1, 9),
            reason: 'an 8h mark at 0$h:00 must defer to 09:00');
      }
    });

    /// Regression guard for a defect found while wiring this up.
    ///
    /// firesInQuietHours judges on the DEVICE clock via the epoch. The first
    /// cut of wakeFireTime built the 09:00 deferral on tz.local's calendar
    /// day instead. Those agree in production - but NOT when the zone lookup
    /// falls back to UTC, and then the deferral could resolve to a time
    /// already past, which zonedSchedule rejects by throwing straight out of
    /// setSleepMode. tz.local is pinned to UTC here to hold them apart.
    test('deferral is computed on the device clock even when tz.local is UTC',
        () async {
      tz.setLocalLocation(tz.UTC);
      // An 8h mark at 03:00 on the DEVICE clock, two days out.
      final soon = DateTime.now().add(const Duration(days: 2));
      final target = DateTime(soon.year, soon.month, soon.day, 3);

      await NotificationService().scheduleWakeNotification(
          sleepStartedAt: target.subtract(const Duration(hours: 8)));

      final onDevice = alarms.instantOf(_wakeId).toLocal();
      expect(onDevice.hour, 9, reason: 'deferred to 09:00 device-local');
      expect(onDevice.day, target.day, reason: 'the same device-clock day');
      expect(alarms.instantOf(_wakeId).isAfter(DateTime.now()), isTrue,
          reason: 'a past date would throw out of zonedSchedule');
    });

    test('fires once - no matchDateTimeComponents', () async {
      await NotificationService().scheduleWakeNotification(
          sleepStartedAt: at(0, 14));

      expect(alarms.armed[_wakeId]!['matchDateTimeComponents'], isNull);
    });

    test('carries its own payload, not the unhandled confirm-sleep one',
        () async {
      await NotificationService().scheduleWakeNotification(
          sleepStartedAt: at(0, 14));

      expect(alarms.armed[_wakeId]!['payload'], kNotifPayloadWakeUp);
      expect(
          alarms.armed[_wakeId]!['payload'], isNot(kNotifPayloadConfirmSleep));
    });
  });

  // -- Through the sleep toggle ----------------------------------------------

  group('sleep toggle arms and cancels it', () {
    late AppDatabase db;
    late NotificationService service;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.getSettings();
      service = NotificationService();
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(service),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    SettingsNotifier notifier() =>
        container.read(settingsNotifierProvider.notifier);

    /// What a resume leaves armed, so we can prove none of it is disturbed.
    Future<void> armLikeAResume() async {
      await service.scheduleHourly();
      await service.scheduleWeeklyReflection();
      await service.scheduleInactivityCheck();
      alarms.cancelAllCalls = 0;
    }

    test('on: arms 997 for a time still in the future', () async {
      await notifier().setSleepMode(active: true);

      expect(alarms.ids, contains(_wakeId));
      expect(alarms.instantOf(_wakeId).isAfter(DateTime.now()), isTrue);
    });

    test('off before the 8 hours elapse: 997 is cancelled', () async {
      await notifier().setSleepMode(active: true);
      expect(alarms.ids, contains(_wakeId));

      await notifier().setSleepMode(active: false);

      expect(alarms.ids, isNot(contains(_wakeId)));
    });

    test('on, off, on again re-arms cleanly - exactly one pending', () async {
      await notifier().setSleepMode(active: true);
      await notifier().setSleepMode(active: false);
      await notifier().setSleepMode(active: true);

      expect(alarms.armed.keys.where((id) => id == _wakeId), hasLength(1));
    });

    test('on twice in a row still leaves exactly one pending', () async {
      await notifier().setSleepMode(active: true);
      await notifier().setSleepMode(active: true);

      expect(alarms.armed.keys.where((id) => id == _wakeId), hasLength(1));
    });

    /// Same-id replacement means a duplicate is impossible whether or not the
    /// code cancels first, so the "exactly one pending" assertions above pass
    /// even with the defensive cancel deleted. This pins the cancel itself.
    test('re-arming cancels its own id first, and touches no other', () async {
      await notifier().setSleepMode(active: true);
      await notifier().setSleepMode(active: true);

      expect(alarms.scheduleCalls[_wakeId], 2);
      expect(alarms.cancelCalls[_wakeId], 2,
          reason: 'each schedule cancels 997 before arming it');
      expect(alarms.cancelCalls[998] ?? 0, 0);
      expect(alarms.cancelCalls[999] ?? 0, 0);
    });

    /// The collision the diagnostic flagged: 999 is armed on pause only when
    /// the toggle is OFF, so on the normal path 997 and 999 never coexist.
    /// The risk is an early toggle-off leaving 997 pending when the next pause
    /// arms 999 - which cancelling 997 on toggle-off is what prevents.
    test('after an early toggle-off, a later pause arms 999 with no 997 left',
        () async {
      await notifier().setSleepMode(active: true);
      await notifier().setSleepMode(active: false);

      // What DashboardScreen does on pause when the toggle is off.
      await service.scheduleInactivityCheck();

      expect(alarms.ids, contains(999));
      expect(alarms.ids, isNot(contains(_wakeId)),
          reason: '999 must never be armed on top of a pending 997');
    });

    test('none of this cancels 998, 999 or any reminder id', () async {
      await armLikeAResume();
      expect(alarms.ids.where((id) => id >= 300 && id <= 323), isNotEmpty);

      await notifier().setSleepMode(active: true);

      // Sleep-on cancels reminders by design; 998 and 999 must survive.
      expect(alarms.ids, containsAll([998, 999]));
      expect(alarms.ids, contains(_wakeId));
      expect(alarms.cancelAllCalls, 0, reason: 'cancelAll() on the sleep path');

      await notifier().setSleepMode(active: false);

      expect(alarms.ids, containsAll([998, 999]));
      expect(alarms.ids.where((id) => id >= 300 && id <= 323), isNotEmpty);
      expect(alarms.cancelAllCalls, 0);
    });

    test('the retroactive sleep entry is still written on toggle-off',
        () async {
      await db.updateSettings(UserSettingsCompanion(
        sleepModeActive: const Value(true),
        sleepModeStartedAt:
            Value(DateTime.now().subtract(const Duration(hours: 8))),
      ));

      await notifier().setSleepMode(active: false);

      final entries = await db.logEntriesDao.getAll();
      expect(entries.map((e) => e.description), contains('Sleep'));
    });
  });
}
