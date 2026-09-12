import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DateTimeComponents;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/notifications/notification_service.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/settings_provider.dart';

/// Stands in for Android's AlarmManager as seen through
/// flutter_local_notifications' method channel: `zonedSchedule` arms an id,
/// `cancel` disarms one, `cancelAll` disarms everything.
///
/// Recording at the channel — rather than subclassing NotificationService like
/// dashboard_launch_test's `_FakeNotificationService` — is deliberate. The id
/// arithmetic and the quiet-hour skip live in private members (`_scheduleOne`,
/// the scheduling loops) that a subclass cannot intercept, so a Dart fake
/// could only count calls. Faking one layer lower runs the REAL service end to
/// end and asserts on exactly what would reach the OS.
class _AlarmTable {
  final armed = <int, Map<Object?, Object?>>{};
  int cancelAllCalls = 0;

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'zonedSchedule':
        final m = args as Map<Object?, Object?>;
        armed[m['id']! as int] = m;
      case 'cancel':
        armed.remove((args as Map<Object?, Object?>)['id']);
      case 'cancelAll':
        cancelAllCalls++;
        armed.clear();
      case 'initialize':
        // The plugin types this as Future<bool>; null would throw.
        return true;
    }
    return null;
  }

  Set<int> get ids => armed.keys.toSet();
  Set<int> get hourlyIds =>
      {for (final id in ids) if (id >= 300 && id <= 323) id};
  Set<int> get intervalIds =>
      {for (final id in ids) if (id >= 100 && id <= 147) id};
  Set<int> get reminderIds => {...hourlyIds, ...intervalIds};

  /// The absolute instant an armed alarm fires.
  DateTime instantOf(int id) =>
      DateTime.parse(armed[id]!['scheduledDateTimeISO8601']! as String);

  /// The wall-clock time in the alarm's OWN zone (what the plugin hands
  /// Android alongside `timeZoneName`).
  DateTime wallClockOf(int id) =>
      DateTime.parse(armed[id]!['scheduledDateTime']! as String);
}

// The spec, restated here independently of the production constants.
bool _quiet(int hour) => hour >= 1 && hour < 9;

/// The hour the user sees on their own phone when [instant] arrives.
int _deviceHour(DateTime instant) => instant.toLocal().hour;

void _expectNoneQuiet(_AlarmTable alarms, Iterable<int> ids) {
  for (final id in ids) {
    final at = alarms.instantOf(id).toLocal();
    expect(_quiet(_deviceHour(at)), isFalse,
        reason: 'id $id fires at $at on the device clock — inside quiet hours');
  }
}

/// Every surviving custom-interval alarm must sit on its ORIGINAL slot:
/// id 100+i fires at now + interval·(i+1), for one shared `now`. Proves quiet
/// slots were skipped, not shifted later, and that the id scheme is intact.
void _expectOnOriginalGrid(_AlarmTable alarms, int intervalMinutes) {
  final anchors = {
    for (final id in alarms.intervalIds)
      alarms
          .instantOf(id)
          .subtract(Duration(minutes: intervalMinutes * (id - 100 + 1))),
  };
  expect(anchors, hasLength(1),
      reason: 'all surviving slots must share one `now` anchor');
}

/// A zone whose clock agrees with the device's right now, so `tz.local` and
/// the device clock coincide — the situation in which the spec's "ids 301
/// through 308" framing holds literally.
tz.Location _zoneAgreeingWithDevice() {
  final offset = DateTime.now().timeZoneOffset;
  // The `latest` database production loads carries no Etc/GMT± zones, so
  // match on the current offset instead (the device's own zone is in there).
  return tz.timeZoneDatabase.locations.values
      .firstWhere((l) => tz.TZDateTime.now(l).timeZoneOffset == offset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late _AlarmTable alarms;

  setUpAll(tzdata.initializeTimeZones);

  setUp(() {
    // The worst case, not the common one: init() now installs the device zone
    // via initDeviceTimeZone(), but falls back to UTC when the platform lookup
    // fails. Pinning UTC here keeps these asserting the case where tz.local
    // and the device clock DISAGREE — the one the quiet-hour skip must survive.
    tz.setLocalLocation(tz.UTC);
    alarms = _AlarmTable();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, alarms.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // ── Hourly mode ───────────────────────────────────────────────────────────

  group('hourly mode', () {
    test('registers 16 alarms, none landing in 01:00–08:59 on the device clock',
        () async {
      await NotificationService().scheduleHourly();

      expect(alarms.ids, hasLength(16));
      expect(alarms.ids.every((id) => id >= 300 && id <= 323), isTrue);
      _expectNoneQuiet(alarms, alarms.ids);
    });

    test(
        'when tz.local agrees with the device clock, exactly ids 301–308 '
        'are the ones not registered', () async {
      tz.setLocalLocation(_zoneAgreeingWithDevice());

      await NotificationService().scheduleHourly();

      expect(alarms.ids, {300, for (var h = 9; h < 24; h++) 300 + h});
    });

    test('id scheme unchanged: id 300+h fires daily at h:00 in its own zone',
        () async {
      await NotificationService().scheduleHourly();

      for (final id in alarms.ids) {
        final wall = alarms.wallClockOf(id);
        expect(wall.hour, id - 300);
        expect(wall.minute, 0);
        expect(alarms.armed[id]!['matchDateTimeComponents'],
            DateTimeComponents.time.index);
      }
    });

    test('still begins with cancelAll()', () async {
      await NotificationService().scheduleHourly();
      expect(alarms.cancelAllCalls, 1);
    });
  });

  // ── Custom interval mode ──────────────────────────────────────────────────

  group('custom interval mode', () {
    test('at 60 min: 32 of 48 slots survive, none quiet, none shifted',
        () async {
      await NotificationService().scheduleCustomInterval(intervalMinutes: 60);

      // 48 hourly slots cover each clock hour exactly twice; 8 quiet hours
      // × 2 = 16 skipped.
      expect(alarms.ids, hasLength(32));
      expect(alarms.ids, alarms.intervalIds);
      _expectNoneQuiet(alarms, alarms.ids);
      _expectOnOriginalGrid(alarms, 60);
    });

    test('at 180 min: some slots skipped, survivors unshifted and not quiet',
        () async {
      await NotificationService().scheduleCustomInterval(intervalMinutes: 180);

      // Any 8-hour window holds 2–3 of every 3-hourly residue class, so at
      // least 12 of the 48 slots always land in quiet hours.
      expect(alarms.ids.length, lessThanOrEqualTo(36));
      expect(alarms.ids, alarms.intervalIds);
      _expectNoneQuiet(alarms, alarms.ids);
      _expectOnOriginalGrid(alarms, 180);
    });

    test('still begins with cancelAll()', () async {
      await NotificationService().scheduleCustomInterval(intervalMinutes: 60);
      expect(alarms.cancelAllCalls, 1);
    });
  });

  // ── Timezone installation ─────────────────────────────────────────────────

  group('init() installs the device zone', () {
    const tzChannel = MethodChannel('flutter_timezone');

    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzChannel, null));

    /// The regression guard for the Monday-02:00 bug. init() used to leave
    /// tz.local at UTC, so every tz.TZDateTime(tz.local, ...) was a UTC wall
    /// clock. With tz.local pinned to UTC beforehand, this fails on the old
    /// code and passes on the new.
    test('tz.local becomes the reported zone, not UTC', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, (_) async => 'Asia/Dhaka');
      tz.setLocalLocation(tz.UTC);

      await NotificationService().init();

      expect(tz.local.name, 'Asia/Dhaka');
      expect(tz.local, isNot(tz.UTC));
    });

    test('a Sunday 20:00 reflection scheduled after init() is 20:00 in that '
        'zone — not Monday 02:00', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, (_) async => 'Asia/Dhaka');
      tz.setLocalLocation(tz.UTC);
      final service = NotificationService();
      await service.init();

      await service.scheduleWeeklyReflection();

      // Expressed in Asia/Dhaka explicitly, NOT tz.local: reading it back
      // through tz.local would be tautological, passing on the old code too
      // (Sunday 20:00 UTC read in UTC is still hour 20). Pre-fix this instant
      // is Sunday 20:00 UTC, which is Monday 02:00 in Dhaka.
      final dhaka =
          tz.TZDateTime.from(alarms.instantOf(998), tz.getLocation('Asia/Dhaka'));
      expect(dhaka.hour, 20);
      expect(dhaka.weekday, DateTime.sunday);
    });
  });

  // ── The real configuration: tz.local installed BY init() ──────────────────

  group('after init() installs the device zone', () {
    const tzChannel = MethodChannel('flutter_timezone');

    /// Reports THIS machine's own zone, so the assertions below hold wherever
    /// the suite runs rather than only at UTC+6.
    void platformReportsThisMachinesZone() {
      final name = _zoneAgreeingWithDevice().name;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tzChannel, (_) async => name);
    }

    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(tzChannel, null));

    /// The phase 2 test 'when tz.local agrees with the device clock, exactly
    /// ids 301-308 are the ones not registered' asserted this while SETTING
    /// tz.local by hand. This is the same assertion reached the production
    /// way — through init() — which is what makes it true in the real app.
    test('the skipped hourly ids are exactly 301-308, reached via init()',
        () async {
      platformReportsThisMachinesZone();
      tz.setLocalLocation(tz.UTC);
      final service = NotificationService();
      await service.init();

      await service.scheduleHourly();

      expect(alarms.ids, {300, for (var h = 9; h < 24; h++) 300 + h});
      expect(alarms.ids, hasLength(16));
    });

    /// The candidate-time arithmetic: with tz.local correct, now.year/month/day
    /// is the LOCAL date, so 'build today at h:00, push a day if already past'
    /// must yield the next occurrence of each local hour - 24 distinct
    /// instants, every one inside (now, now+24h].
    test('the 24 candidates are the next occurrence of each local hour',
        () async {
      platformReportsThisMachinesZone();
      tz.setLocalLocation(tz.UTC);
      final service = NotificationService();
      await service.init();
      final before = tz.TZDateTime.now(tz.local);

      await service.scheduleHourly();

      final after = tz.TZDateTime.now(tz.local);
      for (final id in alarms.ids) {
        final fire = tz.TZDateTime.from(alarms.instantOf(id), tz.local);
        // id encodes the local hour, and the minute is the top of it.
        expect(fire.hour, id - 300);
        expect(fire.minute, 0);
        // Strictly ahead, and never more than a day out.
        expect(fire.isAfter(before), isTrue, reason: 'id $id is in the past');
        expect(
            fire.isBefore(after.add(const Duration(days: 1, seconds: 1))), isTrue,
            reason: 'id $id is more than 24h out');
      }
      // 16 survivors, all distinct instants.
      expect({for (final id in alarms.ids) alarms.instantOf(id)}, hasLength(16));
    });
  });

  // ── Weekly reflection ─────────────────────────────────────────────────────

  group('weekly reflection (998)', () {
    // The bug this covers: with tz.local left at UTC, "Sunday 20:00" was built
    // on a UTC wall clock and reached a UTC+6 user at Monday 02:00 — inside
    // quiet hours. Fixed by init() installing the device zone, so the assertion
    // is on the DEVICE clock, which is what the user reads off their phone.
    test('fires Sunday 20:00 on the device clock when tz.local is that zone',
        () async {
      tz.setLocalLocation(_zoneAgreeingWithDevice());

      await NotificationService().scheduleWeeklyReflection();

      final at = alarms.instantOf(998).toLocal();
      expect(at.weekday, DateTime.sunday);
      expect(at.hour, 20);
      expect(at.minute, 0);
    });

    test('is in the future and repeats weekly', () async {
      tz.setLocalLocation(_zoneAgreeingWithDevice());

      await NotificationService().scheduleWeeklyReflection();

      expect(alarms.instantOf(998).isAfter(DateTime.now()), isTrue);
      expect(alarms.armed[998]!['matchDateTimeComponents'],
          DateTimeComponents.dayOfWeekAndTime.index);
    });

    test('never lands in quiet hours once tz.local is the device zone',
        () async {
      tz.setLocalLocation(_zoneAgreeingWithDevice());

      await NotificationService().scheduleWeeklyReflection();

      _expectNoneQuiet(alarms, [998]);
    });
  });

  // ── Sleep toggle ──────────────────────────────────────────────────────────

  group('sleep toggle', () {
    late AppDatabase db;
    late NotificationService service;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.getSettings(); // seeds the singleton settings row
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

    /// The state a resume leaves behind: reminders, weekly reflection (998),
    /// and — once the app is backgrounded — the inactivity check (999).
    Future<void> armLikeAResume({required bool custom}) async {
      if (custom) {
        await service.scheduleCustomInterval(intervalMinutes: 60);
      } else {
        await service.scheduleHourly();
      }
      await service.scheduleWeeklyReflection();
      await service.scheduleInactivityCheck();
      alarms.cancelAllCalls = 0;
    }

    Future<void> startSleeping() => db.updateSettings(UserSettingsCompanion(
          sleepModeActive: const Value(true),
          sleepModeStartedAt:
              Value(DateTime.now().subtract(const Duration(hours: 8))),
        ));

    test('on: cancels every hourly reminder; 997, 998 and 999 stay armed',
        () async {
      await armLikeAResume(custom: false);
      expect(alarms.hourlyIds, isNotEmpty);

      await notifier().setSleepMode(active: true);

      // 997 joined this set in phase 3: sleep-on now also arms the wake nudge.
      expect(alarms.ids, {997, 998, 999});
      expect(alarms.cancelAllCalls, 0,
          reason: 'cancelAll() would take 998 and 999 with it');
      expect((await db.getSettings()).sleepModeActive, isTrue);
    });

    test('on: cancels every custom-interval reminder; 997, 998, 999 stay armed',
        () async {
      await armLikeAResume(custom: true);
      expect(alarms.intervalIds, isNotEmpty);

      await notifier().setSleepMode(active: true);

      expect(alarms.ids, {997, 998, 999});
      expect(alarms.cancelAllCalls, 0);
    });

    test(
        'off: re-arms hourly reminders for the stored (default) mode, quiet '
        'hours respected, 998/999 untouched', () async {
      await startSleeping();
      await service.scheduleWeeklyReflection();
      await service.scheduleInactivityCheck();
      alarms.cancelAllCalls = 0;

      await notifier().setSleepMode(active: false);

      expect(alarms.hourlyIds, hasLength(16));
      expect(alarms.intervalIds, isEmpty);
      _expectNoneQuiet(alarms, alarms.reminderIds);
      expect(alarms.ids, containsAll([998, 999]));
      expect(alarms.cancelAllCalls, 0);

      // The retroactive sleep entry is still written, unchanged.
      final entries = await db.logEntriesDao.getAll();
      expect(entries.map((e) => e.description), contains('Sleep'));
      expect((await db.getSettings()).sleepModeActive, isFalse);
    });

    test('off: re-arms custom-interval reminders at the stored interval',
        () async {
      await db.updateSettings(const UserSettingsCompanion(
        reminderMode: Value('custom'),
        strictIntervalMinutes: Value(60),
      ));
      await startSleeping();
      await service.scheduleWeeklyReflection();
      alarms.cancelAllCalls = 0;

      await notifier().setSleepMode(active: false);

      expect(alarms.intervalIds, hasLength(32));
      expect(alarms.hourlyIds, isEmpty);
      _expectNoneQuiet(alarms, alarms.reminderIds);
      _expectOnOriginalGrid(alarms, 60);
      expect(alarms.ids, contains(998));
      expect(alarms.cancelAllCalls, 0);
    });

    test('off: legacy "strict" mode is treated as custom, same as _onResume',
        () async {
      await db.updateSettings(const UserSettingsCompanion(
        reminderMode: Value('strict'),
        strictIntervalMinutes: Value(120),
      ));
      await startSleeping();

      await notifier().setSleepMode(active: false);

      expect(alarms.intervalIds, isNotEmpty);
      expect(alarms.hourlyIds, isEmpty);
      _expectOnOriginalGrid(alarms, 120);
    });
  });
}
