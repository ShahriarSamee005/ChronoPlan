import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/notifications/notification_service.dart';
import 'package:chronoplan/features/dashboard/dashboard_screen.dart';
import 'package:chronoplan/providers/database_provider.dart';

/// Stand-in for the real service so the resume path doesn't reach
/// flutter_local_notifications' method channel (which throws
/// MissingPluginException headless). Also records that _onResume actually
/// ran — the point of the fix is to defer the priming call, not delete it.
class _FakeNotificationService extends NotificationService {
  int cancelInactivityCheckCalls = 0;
  int scheduleCalls = 0;
  final _taps = StreamController<String>.broadcast();

  @override
  Stream<String> get tapStream => _taps.stream;

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
  // The priming call is post-frame now, so let that frame land and give the
  // async DB work inside _onResume a couple of turns to settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// _LiveClock (current_hour_card.dart) opens its minute ticker with an
/// uncancellable `Future.delayed` to the next minute boundary — nothing
/// disposes that one, so the tree has to come down FIRST and the clock be
/// run out after, where `_startTicking`'s `if (!mounted) return` swallows it
/// without arming the periodic Timer. Otherwise every test here trips
/// "A Timer is still pending even after the widget tree was disposed."
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 61));
}

void main() {
  // The real screen is pumped rather than a synthetic repro: the bug was in
  // DashboardScreen's own initState, and the usage/permission providers it
  // invalidates are already no-ops off Android (`if (!Platform.isAndroid)`),
  // so the only thing needing a stand-in is the notification service.

  testWidgets(
    'cold start: DashboardScreen builds without the '
    'dependOnInheritedWidgetOfExactType-before-initState crash',
    (tester) async {
      final db = await _memoryDb(tester);
      final notif = _FakeNotificationService();

      await _pumpDashboard(tester, db, notif);

      // Before the fix this is an assertion error from ref.invalidate
      // dereferencing Riverpod's `late _container` inside initState:
      //   "dependOnInheritedWidgetOfExactType<UncontrolledProviderScope>()
      //    was called before _DashboardScreenState.initState() completed."
      expect(
        tester.takeException(),
        isNull,
        reason: 'launching the dashboard must not throw during initState',
      );
      expect(find.byType(DashboardScreen), findsOneWidget);

      await _teardown(tester);
      notif.dispose();
      await tester.runAsync(() => db.close());
    },
  );

  testWidgets(
    'cold start still primes _onResume — deferring it must not drop it '
    '(no `resumed` lifecycle event is delivered on first launch)',
    (tester) async {
      final db = await _memoryDb(tester);
      final notif = _FakeNotificationService();

      await _pumpDashboard(tester, db, notif);

      expect(tester.takeException(), isNull);
      expect(
        notif.cancelInactivityCheckCalls,
        greaterThanOrEqualTo(1),
        reason: '_onResume must still run on cold start, just post-frame',
      );

      // appOpenCount is bumped by the first statement in _onResume, ahead of
      // the invalidates — proves the whole method body ran, not just its head.
      final settings = await tester.runAsync(() => db.getSettings());
      expect(settings!.appOpenCount, greaterThanOrEqualTo(1));

      await _teardown(tester);
      notif.dispose();
      await tester.runAsync(() => db.close());
    },
  );

  testWidgets(
    'steady state: a real resumed lifecycle event still re-runs _onResume',
    (tester) async {
      final db = await _memoryDb(tester);
      final notif = _FakeNotificationService();

      await _pumpDashboard(tester, db, notif);
      final afterLaunch = notif.cancelInactivityCheckCalls;

      // Full OS background/foreground transition, same as the app really does.
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        notif.cancelInactivityCheckCalls,
        greaterThan(afterLaunch),
        reason: 'didChangeAppLifecycleState(resumed) wiring must be intact',
      );

      await _teardown(tester);
      notif.dispose();
      await tester.runAsync(() => db.close());
    },
  );
}
