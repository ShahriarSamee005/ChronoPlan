import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/notifications/notification_service.dart';
import 'package:chronoplan/core/theme/glass_card.dart';
import 'package:chronoplan/features/dashboard/dashboard_screen.dart';
import 'package:chronoplan/features/dashboard/widgets/current_hour_card.dart';
import 'package:chronoplan/features/dashboard/widgets/notification_permission_card.dart';
import 'package:chronoplan/features/dashboard/widgets/sleep_active_card.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/settings_provider.dart';

/// The Dashboard card that shows while sleep mode is on.
///
/// Test 5 is the load-bearing one: it drives the REAL `setSleepMode` against a
/// REAL in-memory Drift database and asserts the card appears and disappears on
/// its own. Nothing in this file calls `ref.invalidate` or `ref.refresh`, so the
/// only thing that can move the UI is `watchSettings()` emitting — which is
/// exactly the property that breaks if `settingsProvider` stops streaming.

/// Stand-in for the real service so neither the resume path nor `setSleepMode`
/// reaches flutter_local_notifications' method channel (MissingPluginException
/// headless). Covers both sets of calls: the four `_onResume`/`_onPause` makes,
/// and the four `setSleepMode` makes on its sleep and wake paths.
class _FakeNotificationService extends NotificationService {
  int cancelInactivityCheckCalls = 0;
  int scheduleCalls = 0;
  int wakeArmed = 0;
  int wakeCancelled = 0;
  final _taps = StreamController<String>.broadcast();

  @override
  Stream<String> get tapStream => _taps.stream;

  // ── DashboardScreen._onResume / _onPause ────────────────────────────────
  @override
  Future<void> cancelInactivityCheck() async => cancelInactivityCheckCalls++;

  @override
  Future<void> scheduleHourly() async => scheduleCalls++;

  @override
  Future<void> scheduleCustomInterval({required int intervalMinutes}) async =>
      scheduleCalls++;

  @override
  Future<void> scheduleWeeklyReflection() async => scheduleCalls++;

  @override
  Future<void> scheduleInactivityCheck() async {}

  // ── SettingsNotifier.setSleepMode ───────────────────────────────────────
  @override
  Future<void> cancelReminders() async {}

  @override
  Future<void> rescheduleReminders({
    required String reminderMode,
    required int intervalMinutes,
  }) async {}

  @override
  Future<void> scheduleWakeNotification({
    required DateTime sleepStartedAt,
  }) async =>
      wakeArmed++;

  @override
  Future<void> cancelWakeNotification() async => wakeCancelled++;

  @override
  void dispose() {
    _taps.close();
    super.dispose();
  }
}

Future<AppDatabase> _memoryDb(WidgetTester tester) {
  return tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    // Seeds the singleton settings row AND the 11 default categories, 'Sleep'
    // among them — which setSleepMode(active: false) looks up by name.
    await db.getSettings();
    return db;
  }).then((v) => v!);
}

ProviderContainer _container(AppDatabase db, _FakeNotificationService notif) =>
    ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      notificationServiceProvider.overrideWithValue(notif),
    ]);

/// Writes sleep state straight to the row, bypassing setSleepMode — for the
/// tests that are about RENDERING a given state, not about the toggle.
Future<void> _writeSleep(
  WidgetTester tester,
  AppDatabase db, {
  required bool active,
  required DateTime? startedAt,
  int? appOpens,
}) {
  return tester.runAsync(() => db.updateSettings(UserSettingsCompanion(
        sleepModeActive: Value(active),
        sleepModeStartedAt: Value(startedAt),
        appOpenCount:
            appOpens == null ? const Value.absent() : Value(appOpens),
      )));
}

/// Lets the real sqlite3 work and the Drift stream emission land — they need a
/// REAL async window, which `pump` alone does not give — then rebuilds on
/// bounded pumps.
///
/// Deliberately not pumpAndSettle: CurrentHourCard's _LiveClock ticker and
/// DailyIntentionCard's _BlinkingCursor never stop, so settling never returns.
Future<void> _flush(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

/// Awaits real database work while ALSO letting the test's fake clock advance.
///
/// `tester.runAsync` alone is not enough for `setSleepMode`. Drift delivers its
/// stream-query refreshes in whichever zone subscribed — here the fake-clock
/// zone `pumpWidget` ran in — and `runAsync` advances real time only, never that
/// clock. So a WRITE followed by a READ inside a single `runAsync` block
/// deadlocks: the read queues behind a refresh that can never run.
/// `setSleepMode(active: false)` does exactly that (it writes the row, then
/// re-reads it for the reminder mode), and hangs forever under plain `runAsync`.
///
/// Interleaving real async turns with fake-clock pumps lets both halves make
/// progress. Verified: the same sequence deadlocks with `runAsync` and passes
/// here, and with no stream subscribed it never deadlocks at all.
Future<void> _settle(WidgetTester tester, Future<void> work) async {
  var done = false;
  Object? err;
  StackTrace? st;
  work.then<void>((_) => done = true, onError: (Object e, StackTrace s) {
    err = e;
    st = s;
    done = true;
  });
  for (var i = 0; i < 400 && !done; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    if (done) break;
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (!done) fail('database work never completed');
  if (err != null) Error.throwWithStackTrace(err!, st!);
}

Future<void> _pumpCard(
  WidgetTester tester,
  ProviderContainer container, {
  required VoidCallback onTap,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Align keeps the height constraint loose so the card shrink-wraps to its
      // real height, the same way the Dashboard's ListView lets it.
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SleepActiveCard(onTap: onTap),
          ),
        ),
      ),
    ),
  );
  await _flush(tester);
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  // _onResume is primed post-frame; give that frame and its async DB work a few
  // turns, then flush the settings stream.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await _flush(tester);
}

/// _LiveClock (current_hour_card.dart) opens its minute ticker with an
/// uncancellable `Future.delayed` to the next minute boundary — nothing disposes
/// that one, so the tree has to come down FIRST and the clock be run out after,
/// where `_startTicking`'s `if (!mounted) return` swallows it without arming the
/// periodic Timer. Same reasoning as dashboard_launch_test.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 61));
}

Future<void> _close(
  WidgetTester tester,
  ProviderContainer container,
  _FakeNotificationService notif,
  AppDatabase db,
) async {
  await _teardown(tester);
  container.dispose();
  // Riverpod tears the StreamProvider's drift subscription down on a SCHEDULED
  // callback, and `runAsync` does not advance the test's fake clock — so without
  // a pump here that stream query stays registered and `db.close()` blocks
  // forever. Advancing the fake clock is the only thing that releases it.
  await tester.pump(const Duration(seconds: 1));
  notif.dispose();
  await tester.runAsync(() => db.close());
}

void main() {
  // ── Widget level ────────────────────────────────────────────────────────

  testWidgets('1. sleep off renders nothing at all', (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    final container = _container(db, notif);

    // The seeded row already has sleepModeActive == false.
    await _pumpCard(tester, container, onTap: () {});

    expect(find.text('Sleep mode is on'), findsNothing);
    expect(tester.getSize(find.byType(SleepActiveCard)).height, 0,
        reason: 'the hidden card must occupy no vertical space');

    await _close(tester, container, notif, db);
  });

  testWidgets(
      '2. sleep on with a start time renders both lines, the second reading '
      '"Since h:mm a"', (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    final container = _container(db, notif);

    await _writeSleep(tester, db,
        active: true, startedAt: DateTime(2026, 3, 4, 23, 40));
    await _pumpCard(tester, container, onTap: () {});

    expect(find.text('Sleep mode is on'), findsOneWidget);
    expect(find.text('Since 11:40 PM'), findsOneWidget,
        reason: "DateFormat('h:mm a') — the app convention for this field");

    await _close(tester, container, notif, db);
  });

  testWidgets(
      '3. sleep on with a NULL start time renders the first line only, no '
      '"Since" line and no exception', (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    final container = _container(db, notif);

    // Should not happen — setSleepMode writes both columns in one patch — but
    // sleepModeStartedAt IS nullable, so the card must not assume.
    await _writeSleep(tester, db, active: true, startedAt: null);
    await _pumpCard(tester, container, onTap: () {});

    expect(find.text('Sleep mode is on'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('Since'),
      ),
      findsNothing,
      reason: 'no second line at all — not "Since null"',
    );
    expect(tester.takeException(), isNull);

    await _close(tester, container, notif, db);
  });

  testWidgets('4. tapping the card fires onTap exactly once', (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    final container = _container(db, notif);

    var taps = 0;
    await _writeSleep(tester, db,
        active: true, startedAt: DateTime(2026, 3, 4, 23, 40));
    await _pumpCard(tester, container, onTap: () => taps++);

    expect(find.byType(GlassCard), findsOneWidget);
    await tester.tap(find.text('Sleep mode is on'));
    await tester.pump();

    expect(taps, 1);

    await _close(tester, container, notif, db);
  });

  // ── Reactivity — the load-bearing one ───────────────────────────────────

  testWidgets(
      '5. the real setSleepMode makes the card appear and disappear on its own, '
      'with no invalidate and no manual refresh', (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    final container = _container(db, notif);

    await _pumpCard(tester, container, onTap: () {});
    expect(find.text('Sleep mode is on'), findsNothing,
        reason: 'the seeded row starts with sleep off');

    // The REAL notifier against the REAL in-memory DB. The only thing that can
    // move the UI from here is AppDatabase.watchSettings() emitting.
    final notifier = container.read(settingsNotifierProvider.notifier);

    await _settle(tester, notifier.setSleepMode(active: true));
    await _flush(tester);

    expect(find.text('Sleep mode is on'), findsOneWidget,
        reason: 'the Drift stream must push the new row into the card — this '
            'fails the moment settingsProvider stops streaming');
    expect(notif.wakeArmed, 1, reason: 'the toggle really ran, end to end');

    await _settle(tester, notifier.setSleepMode(active: false));
    await _flush(tester);

    expect(find.text('Sleep mode is on'), findsNothing,
        reason: 'and it must disappear the same way it arrived');
    expect(notif.wakeCancelled, 1);
    expect(tester.takeException(), isNull);

    await _close(tester, container, notif, db);
  });

  // ── Dashboard level ─────────────────────────────────────────────────────

  testWidgets(
      '6. on the real Dashboard the card sits ABOVE '
      'NotificationPermissionCard', (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    final container = _container(db, notif);

    // appOpenCount >= 2 makes NotificationPermissionCard render its FULL card
    // rather than collapsing to SizedBox.shrink(). That matters: a zero-extent
    // child at the leading edge gets dropped from the sliver entirely, and then
    // this test would fail on a missing finder instead of on the geometry.
    // With both cards real, the offset comparison below is the actual assertion.
    await _writeSleep(tester, db,
        active: true, startedAt: DateTime(2026, 3, 4, 23, 40), appOpens: 5);
    await _pumpDashboard(tester, container);

    expect(find.text('Sleep mode is on'), findsOneWidget);
    expect(find.text('Turn On Reminders'), findsOneWidget,
        reason: 'the permission card must really be on screen to measure');

    // Real geometry, not tree order.
    final cardY = tester.getTopLeft(find.text('Sleep mode is on')).dy;
    final notifY =
        tester.getTopLeft(find.byType(NotificationPermissionCard)).dy;

    expect(cardY, lessThan(notifY),
        reason: 'SleepActiveCard must be the FIRST child of the ListView');

    await _close(tester, container, notif, db);
  });

  testWidgets(
      '7. with sleep off the Dashboard has no 12px hole — the self-carried '
      'Padding is not in the tree at all', (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    final container = _container(db, notif);

    await _pumpDashboard(tester, container);

    expect(find.text('Sleep mode is on'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SleepActiveCard),
        matching: find.byType(Padding),
      ),
      findsNothing,
      reason: 'the self-carried bottom gap must vanish with the card',
    );
    // Collapsed to SizedBox.shrink(), the card has zero extent at the leading
    // edge, so RenderSliverList may drop it from the tree altogether. Either
    // outcome means no hole — but if it IS built it must measure zero.
    final built = find.byType(SleepActiveCard).evaluate();
    if (built.isNotEmpty) {
      expect(tester.getSize(find.byType(SleepActiveCard)).height, 0);
    }

    // The real proof there is no 12px hole: the next card sits at the very top
    // of the list while sleep is off, and only moves down once the card shows.
    final offsetWhileOff = tester.getTopLeft(find.byType(CurrentHourCard)).dy;

    await _writeSleep(tester, db,
        active: true, startedAt: DateTime(2026, 3, 4, 23, 40));
    await _flush(tester);

    expect(find.text('Sleep mode is on'), findsOneWidget);
    final offsetWhileOn = tester.getTopLeft(find.byType(CurrentHourCard)).dy;

    expect(offsetWhileOff, lessThan(offsetWhileOn),
        reason: 'the hidden card must consume no vertical space at all — if it '
            'left a 12px gap these two offsets would match');

    await _close(tester, container, notif, db);
  });
}
