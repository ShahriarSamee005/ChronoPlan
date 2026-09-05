import 'dart:async';

import 'package:chronoplan/core/analytics/analytics_service.dart';
import 'package:chronoplan/core/analytics/used_ai_store.dart';
import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/notifications/notification_service.dart';
import 'package:chronoplan/features/dashboard/dashboard_screen.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same stand-in the launch test uses — keeps `_onResume` off the notification
/// method channel and records that the resume path actually ran.
class _FakeNotificationService extends NotificationService {
  final _taps = StreamController<String>.broadcast();
  @override
  Stream<String> get tapStream => _taps.stream;
  @override
  Future<void> cancelInactivityCheck() async {}
  @override
  Future<void> scheduleHourly() async {}
  @override
  Future<void> scheduleCustomInterval({required int intervalMinutes}) async {}
  @override
  Future<void> scheduleWeeklyReflection() async {}
  @override
  Future<void> scheduleInactivityCheck() async {}
  @override
  void dispose() {
    _taps.close();
    super.dispose();
  }
}

/// Counts pingIfDue calls without doing anything.
class _CountingAnalyticsService extends AnalyticsService {
  _CountingAnalyticsService(AppDatabase db, UsedAiStore store)
      : super(db: db, usedAiStore: store);
  int pingCalls = 0;
  @override
  Future<void> pingIfDue() async => pingCalls++;
}

/// Real pingIfDue, but the network POST always throws — the end-to-end failure
/// path through `_onResume`.
class _ThrowingAnalyticsService extends AnalyticsService {
  _ThrowingAnalyticsService(AppDatabase db, UsedAiStore store)
      : super(db: db, usedAiStore: store);
  @override
  String? get accessToken => 'fake-access-token';
  @override
  Future<int> postPing(Map<String, dynamic> body, String tok) async =>
      throw Exception('network boom');
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
  NotificationService notif,
  AnalyticsService analytics,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notif),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  // The priming call is post-frame; let it land and settle the async work.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// _LiveClock arms an uncancellable minute ticker; bring the tree down first,
/// then run the clock out so `_startTicking`'s mounted-guard swallows it.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 61));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('dashboard cold start fires pingIfDue exactly once',
      (tester) async {
    final db = await _memoryDb(tester);
    final notif = _FakeNotificationService();
    final analytics = _CountingAnalyticsService(db, UsedAiStore());

    await _pumpDashboard(tester, db, notif, analytics);

    expect(tester.takeException(), isNull);
    expect(analytics.pingCalls, 1,
        reason: '_onResume must fire the ping once on cold start');

    await _teardown(tester);
    notif.dispose();
    await tester.runAsync(() => db.close());
  });

  testWidgets(
    'a failing analytics POST does not throw out of _onResume and leaves '
    'lastSyncedAt unwritten',
    (tester) async {
      final db = await _memoryDb(tester);
      final notif = _FakeNotificationService();
      final analytics = _ThrowingAnalyticsService(db, UsedAiStore());

      await _pumpDashboard(tester, db, notif, analytics);

      expect(tester.takeException(), isNull,
          reason: 'analytics failure must never surface to the UI');
      final settings = await tester.runAsync(() => db.getSettings());
      expect(settings!.lastSyncedAt, isNull,
          reason: 'a failed ping must not advance lastSyncedAt');

      await _teardown(tester);
      notif.dispose();
      await tester.runAsync(() => db.close());
    },
  );
}
