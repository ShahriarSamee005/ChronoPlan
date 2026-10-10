import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/notifications/notification_service.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/settings_provider.dart';

/// The one-time battery-optimisation exemption prompt, shown the FIRST time
/// sleep mode is turned on and never again (Part 1 of the wake-notification fix).
///
/// These drive the REAL `SettingsNotifier.setSleepMode` against a REAL in-memory
/// Drift database. Nothing here subscribes to `settingsProvider`, so there is no
/// Drift stream to deadlock a write-then-read — the notifier's futures can be
/// awaited directly (see sleep_active_card_test for why the stream case needs the
/// interleaving `_settle` helper instead).

/// Stand-in for the real service so `setSleepMode` never reaches a platform
/// channel. Records the two battery calls and lets each test choose whether the
/// app is already exempt. Mirrors sleep_active_card_test's
/// `_FakeNotificationService`; it overrides only the public methods setSleepMode
/// touches.
class _FakeNotificationService extends NotificationService {
  int wakeArmed = 0;
  int wakeCancelled = 0;
  int batteryRequestCalls = 0;
  int batteryCheckCalls = 0;

  /// What `isIgnoringBatteryOptimizations()` reports — the "already exempt" knob.
  bool exempt = false;

  // ── setSleepMode: sleep-on path ─────────────────────────────────────────
  @override
  Future<void> cancelReminders() async {}

  @override
  Future<void> scheduleWakeNotification({
    required DateTime sleepStartedAt,
  }) async =>
      wakeArmed++;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    batteryCheckCalls++;
    return exempt;
  }

  @override
  Future<void> requestIgnoreBatteryOptimizations() async =>
      batteryRequestCalls++;

  // ── setSleepMode: wake path ─────────────────────────────────────────────
  @override
  Future<void> cancelWakeNotification() async => wakeCancelled++;

  @override
  Future<void> rescheduleReminders({
    required String reminderMode,
    required int intervalMinutes,
  }) async {}
}

/// One wired-up notifier over a fresh in-memory DB. `getSettings()` forces the
/// onCreate seed (settings row + default categories) before the test runs.
Future<({AppDatabase db, _FakeNotificationService notif, SettingsNotifier n})>
    _setup({required bool exempt}) async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.getSettings();
  final notif = _FakeNotificationService()..exempt = exempt;
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    notificationServiceProvider.overrideWithValue(notif),
  ]);
  addTearDown(() async => db.close());
  addTearDown(container.dispose);
  return (
    db: db,
    notif: notif,
    n: container.read(settingsNotifierProvider.notifier),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Same sqlite3 load the other DB-backed tests use on this Windows box.
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  test(
      '1. first sleep-on, not exempt: requests exemption once and sets the flag',
      () async {
    final s = await _setup(exempt: false);

    await s.n.setSleepMode(active: true);

    expect(s.notif.batteryRequestCalls, 1,
        reason: 'the system dialog must fire exactly once on first sleep-on');
    expect((await s.db.getSettings()).batteryExemptionAsked, isTrue,
        reason: 'the "asked" flag must be set so we never prompt again');
  });

  test('2. already exempt: does NOT request, but still sets the flag',
      () async {
    final s = await _setup(exempt: true);

    await s.n.setSleepMode(active: true);

    expect(s.notif.batteryRequestCalls, 0,
        reason: 'no dialog when the app is already on the allowlist');
    expect((await s.db.getSettings()).batteryExemptionAsked, isTrue,
        reason: 'still record it as asked so we do not re-check every time');
  });

  test(
      '3. asked once: a second sleep-on never re-requests (load-bearing guard)',
      () async {
    final s = await _setup(exempt: false);

    await s.n.setSleepMode(active: true);
    expect(s.notif.batteryRequestCalls, 1);

    // Second enable with the flag already true — the guard must swallow it.
    await s.n.setSleepMode(active: true);

    expect(s.notif.batteryRequestCalls, 1,
        reason: 'ask ONCE: removing the !batteryExemptionAsked guard breaks this');
    expect((await s.db.getSettings()).batteryExemptionAsked, isTrue);
  });

  test('4. sleep-OFF never requests and never sets the flag', () async {
    final s = await _setup(exempt: false);

    await s.n.setSleepMode(active: false);

    expect(s.notif.batteryRequestCalls, 0);
    expect(s.notif.batteryCheckCalls, 0,
        reason: 'the whole battery block lives inside the active branch');
    expect((await s.db.getSettings()).batteryExemptionAsked, isFalse);
  });

  test('5. the wake notification is armed regardless of the exemption path',
      () async {
    // Self-contained per iteration: close each DB before opening the next so
    // two AppDatabases never coexist (which drift warns about in debug).
    for (final exempt in [true, false]) {
      final db = AppDatabase(NativeDatabase.memory());
      await db.getSettings();
      final notif = _FakeNotificationService()..exempt = exempt;
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notif),
      ]);

      await container
          .read(settingsNotifierProvider.notifier)
          .setSleepMode(active: true);

      expect(notif.wakeArmed, 1,
          reason: 'exempt=$exempt must not gate or skip scheduleWakeNotification');

      container.dispose();
      await db.close();
    }
  });

  test(
      '6. migration v7 -> v8 adds battery_exemption_asked (false) and keeps the row',
      () async {
    final dir = Directory.systemTemp.createTempSync('chronoplan_mig');
    final file = File('${dir.path}/mig.sqlite');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    // Build an "existing v7 database with data": open at the current schema,
    // seed recognisable data, then knock the row back to the v7 shape by
    // dropping every column added after v7 and resetting the stored schema
    // version. This is exactly the state a tester's populated phone is in
    // before the upgrade. Columns added after v7: user_settings
    // .battery_exemption_asked (v8) and intention_tasks.sync_id (v9).
    final old = AppDatabase(NativeDatabase(file));
    await old.updateSettings(UserSettingsCompanion(
      aiPersona: const Value('drill'),
      appOpenCount: const Value(5),
    ));
    await old.customStatement(
        'ALTER TABLE user_settings DROP COLUMN battery_exemption_asked');
    await old.customStatement(
        'ALTER TABLE intention_tasks DROP COLUMN sync_id');
    await old.customStatement('PRAGMA user_version = 7');
    await old.close();

    // Reopen: drift sees user_version 7 < 9 and runs the addColumn migrations.
    final migrated = AppDatabase(NativeDatabase(file));
    addTearDown(() async => migrated.close());

    final settings = await migrated.getSettings();
    expect(settings.batteryExemptionAsked, isFalse,
        reason: 'the migrated column must default to false');
    expect(settings.aiPersona, 'drill',
        reason: 'pre-existing data must survive a pure addColumn migration');
    expect(settings.appOpenCount, 5, reason: 'the row must not be lost');
  });
}
