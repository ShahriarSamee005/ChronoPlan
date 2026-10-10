import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/notifications/notification_service.dart';
import 'package:chronoplan/features/dashboard/dashboard_screen.dart';
import 'package:chronoplan/providers/database_provider.dart';

/// Part 2 of the wake-notification fix: when the app resumes while sleep mode is
/// still on, `_onResume` re-arms the wake nudge (997) from the STORED sleep-start
/// time, restoring an alarm the OS dropped during a long sleep.
///
/// These drive the REAL `DashboardScreen._onResume` (via the post-frame cold-start
/// prime and real `resumed` lifecycle events) against a REAL in-memory DB, with a
/// fake notification service standing in for the method channel. Mirrors
/// dashboard_launch_test's harness — no `pumpAndSettle`, since CurrentHourCard's
/// live clock and DailyIntentionCard's blinking cursor never stop.

/// Records every call `_onResume` makes. `wakeStarts` captures the exact
/// `sleepStartedAt` handed to `scheduleWakeNotification`, so a test can prove the
/// value is the stored start (never a fresh `now`) and is identical across resumes.
class _FakeNotificationService extends NotificationService {
  int cancelInactivityCheckCalls = 0;
  int reminderScheduleCalls = 0; // scheduleHourly / scheduleCustomInterval
  int weeklyReflectionCalls = 0;
  final wakeStarts = <DateTime>[];
  final _taps = StreamController<String>.broadcast();

  @override
  Stream<String> get tapStream => _taps.stream;

  @override
  Future<void> cancelInactivityCheck() async => cancelInactivityCheckCalls++;

  @override
  Future<void> scheduleHourly() async => reminderScheduleCalls++;

  @override
  Future<void> scheduleCustomInterval({required int intervalMinutes}) async =>
      reminderScheduleCalls++;

  @override
  Future<void> scheduleWeeklyReflection() async => weeklyReflectionCalls++;

  @override
  Future<void> scheduleInactivityCheck() async {}

  @override
  Future<void> scheduleWakeNotification({
    required DateTime sleepStartedAt,
  }) async =>
      wakeStarts.add(sleepStartedAt);

  @override
  void dispose() {
    _taps.close();
    super.dispose();
  }
}

Future<AppDatabase> _memoryDb(WidgetTester tester) {
  return tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings(); // seeds the singleton settings row
    return db;
  }).then((v) => v!);
}

/// Writes sleep state straight to the row (bypassing setSleepMode) so the
/// cold-start `_onResume` reads exactly the state under test.
Future<void> _setSleep(
  WidgetTester tester,
  AppDatabase db, {
  required bool active,
  required DateTime? startedAt,
}) {
  return tester.runAsync(() => db.updateSettings(UserSettingsCompanion(
        sleepModeActive: Value(active),
        sleepModeStartedAt: Value(startedAt),
      )));
}

Future<DateTime?> _storedStart(WidgetTester tester, AppDatabase db) => tester
    .runAsync(() => db.getSettings())
    .then((s) => s!.sleepModeStartedAt);

Future<void> _pumpDashboard(
  WidgetTester tester,
  AppDatabase db,
  _FakeNotificationService notif,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notif),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  // The priming call is post-frame; let that frame land and give the async DB
  // work inside _onResume a couple of turns to settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// A real OS foreground event, exactly as the app delivers one.
Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// _LiveClock opens its minute ticker with an uncancellable Future.delayed —
/// nothing disposes that one, so the tree must come down FIRST and the clock be
/// run out after, where `_startTicking`'s `if (!mounted) return` swallows it.
/// Same reasoning as dashboard_launch_test.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 61));
}

void main() {
  testWidgets(
      '1. resume during sleep re-arms 997 with the STORED start (not a fresh now)',
      (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    await _setSleep(tester, db,
        active: true, startedAt: DateTime(2026, 9, 24, 0, 30));

    await _pumpDashboard(tester, db, notif);

    final stored = await _storedStart(tester, db);
    expect(tester.takeException(), isNull);
    expect(notif.wakeStarts, isNotEmpty,
        reason: 'the sleep-on resume branch must re-arm the wake nudge');
    expect(notif.wakeStarts.last, stored,
        reason: 'must arm from the stored sleepModeStartedAt, never DateTime.now()');
    expect(notif.reminderScheduleCalls, 0,
        reason: 'sleep-on must NOT touch reminders — only the wake nudge');
    expect(notif.weeklyReflectionCalls, 0);

    await _teardown(tester);
    notif.dispose();
    await tester.runAsync(() => db.close());
  });

  testWidgets(
      '2. LOAD-BEARING: two resumes arm the SAME time — no forward drift',
      (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    // A fixed past instant: if the re-arm used now(), two resumes at different
    // real-clock instants would record two different start times.
    await _setSleep(tester, db,
        active: true, startedAt: DateTime(2026, 9, 24, 1, 15));

    await _pumpDashboard(tester, db, notif); // resume #1 (cold-start prime)
    expect(notif.wakeStarts, isNotEmpty);
    await _resume(tester); // resume #2
    expect(notif.wakeStarts.length, greaterThanOrEqualTo(2),
        reason: 'both resumes must re-arm');

    final stored = await _storedStart(tester, db);
    expect(tester.takeException(), isNull);
    expect(
      notif.wakeStarts.every((s) => s == stored),
      isTrue,
      reason: 'every re-arm must use the identical stored start — the fire time '
          'is a pure function of it, so identical starts mean identical fire '
          'times. Passing DateTime.now() breaks this.',
    );

    await _teardown(tester);
    notif.dispose();
    await tester.runAsync(() => db.close());
  });

  testWidgets(
      '3. LOAD-BEARING: sleep OFF never re-arms, even with a leftover start time',
      (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    // Sleep is off but a non-null start lingers: this isolates the sleep-ACTIVE
    // guard. If the re-arm ran regardless of the guard, it would fire here.
    await _setSleep(tester, db,
        active: false, startedAt: DateTime(2026, 9, 24, 1, 15));

    await _pumpDashboard(tester, db, notif);
    await _resume(tester);

    expect(tester.takeException(), isNull);
    expect(notif.wakeStarts, isEmpty,
        reason: 'the re-arm belongs only to the sleep-active branch');

    await _teardown(tester);
    notif.dispose();
    await tester.runAsync(() => db.close());
  });

  testWidgets('4. sleep active but null start: skips safely, no throw',
      (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    // Shouldn't happen (setSleepMode writes both together) but the column is
    // nullable, so the branch must not assume.
    await _setSleep(tester, db, active: true, startedAt: null);

    await _pumpDashboard(tester, db, notif);
    await _resume(tester);

    expect(tester.takeException(), isNull,
        reason: 'a null start must be skipped, never dereferenced');
    expect(notif.wakeStarts, isEmpty);

    await _teardown(tester);
    notif.dispose();
    await tester.runAsync(() => db.close());
  });

  testWidgets(
      '5. sleep OFF: the pre-existing reschedule still fires and the new branch '
      'does not disturb it', (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    // Seeded default is sleep off; make it explicit for clarity.
    await _setSleep(tester, db, active: false, startedAt: null);

    await _pumpDashboard(tester, db, notif);

    expect(tester.takeException(), isNull);
    expect(notif.reminderScheduleCalls, greaterThanOrEqualTo(1),
        reason: 'sleep-off must still (re)schedule hourly/interval reminders');
    expect(notif.weeklyReflectionCalls, greaterThanOrEqualTo(1),
        reason: 'sleep-off must still (re)schedule the Sunday reflection');
    expect(notif.wakeStarts, isEmpty,
        reason: 'no wake re-arm on the sleep-off path');

    await _teardown(tester);
    notif.dispose();
    await tester.runAsync(() => db.close());
  });
}
