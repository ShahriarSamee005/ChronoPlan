import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/day_view/day_view_screen.dart';
import 'package:chronoplan/features/log_entry/log_entry_sheet.dart';
import 'package:chronoplan/providers/database_provider.dart';

// Phase 2: tapping an empty hour in Day View opens the day-aware LogEntrySheet
// for the viewed day + tapped hour. On today, future hours are refused up front
// with the sheet's "Cannot log future time." message; past days are never
// blocked. Mirrors the day_view_row_layout harness: in-memory Drift, a surface
// sized so all 24 rows fit (no auto-scroll, so tapAt lands deterministically),
// and bounded pumps because the screen's 1-minute ticker defeats pumpAndSettle.

const double _surfaceW = 800.0;
const double _surfaceH = 1800.0;

Future<AppDatabase> _memoryDb(WidgetTester tester) => tester.runAsync(() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.getSettings(); // force onCreate
      return db;
    }).then((v) => v!);

Future<void> _pump(WidgetTester tester, AppDatabase db,
    {DateTime? initialDate}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => DayViewScreen(initialDate: initialDate),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
}

/// Bounded pump — the now-line ticker means `pumpAndSettle` never terminates.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Lets a modal bottom-sheet route animate fully in without settling.
Future<void> _openSheetPump(WidgetTester tester) async {
  await tester.pump(); // kick off the route push
  await tester.pump(const Duration(milliseconds: 400)); // finish the animation
}

Future<void> _teardown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {});
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(() => db.close());
}

Future<void> _log(
  WidgetTester tester,
  AppDatabase db, {
  required DateTime start,
  required DateTime end,
  required String description,
}) =>
    tester.runAsync(() => db.logEntriesDao.insertRetroactive(
          startTime: start,
          endTime: end,
          categoryId: null,
          description: description,
        ));

Finder _seg(int entryId, int hour, {int lane = 0}) =>
    find.byKey(ValueKey('seg_${entryId}_${hour}_$lane'));

/// Taps inside an hour's track (right of the gutter label), the empty-area
/// GestureDetector — same technique as the routine empty-hour test.
Future<void> _tapEmptyHour(WidgetTester tester, int hour) async {
  final label = '${hour.toString().padLeft(2, '0')}:00';
  final labelY = tester.getCenter(find.text(label)).dy;
  await tester.tapAt(Offset(400, labelY));
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  DateTime at(DateTime day, int h, [int m = 0]) =>
      DateTime(day.year, day.month, day.day, h, m);

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(_surfaceW, _surfaceH);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('past day: tapping an empty hour opens the sheet at that day+hour',
      (tester) async {
    final db = await _memoryDb(tester);
    await _pump(tester, db, initialDate: yesterday);

    await _tapEmptyHour(tester, 8);
    await _openSheetPump(tester);

    expect(find.byType(LogEntrySheet), findsOneWidget);
    // Create-mode header: "Logging: 8:00 AM – 9:00 AM" — proves the 08:00 seed.
    expect(find.textContaining('Logging:'), findsOneWidget);
    expect(find.textContaining('8:00'), findsWidgets);

    await _teardown(tester, db);
  });

  testWidgets(
      'today: tapping an empty hour later than now is refused with the message',
      (tester) async {
    if (now.hour >= 23) {
      // No future hour exists on today at 23:xx — nothing to exercise.
      return;
    }
    final db = await _memoryDb(tester);
    await _pump(tester, db, initialDate: today);

    await _tapEmptyHour(tester, now.hour + 1);
    await _openSheetPump(tester);

    expect(find.byType(LogEntrySheet), findsNothing,
        reason: 'a future hour must not open a sheet');
    expect(find.text('Cannot log future time.'), findsOneWidget);

    await _teardown(tester, db);
  });

  testWidgets('today: tapping an empty hour earlier than now opens the sheet',
      (tester) async {
    if (now.hour < 1) {
      // No earlier hour exists on today at 00:xx.
      return;
    }
    final db = await _memoryDb(tester);
    await _pump(tester, db, initialDate: today);

    await _tapEmptyHour(tester, now.hour - 1);
    await _openSheetPump(tester);

    expect(find.byType(LogEntrySheet), findsOneWidget);
    expect(find.text('Cannot log future time.'), findsNothing);

    await _teardown(tester, db);
  });

  testWidgets('tapping an existing segment still opens the EDIT sheet',
      (tester) async {
    final db = await _memoryDb(tester);
    // Logged on yesterday so it is well clear of "now" regardless of run time.
    await _log(tester, db,
        start: at(yesterday, 10), end: at(yesterday, 11), description: 'Work');
    await _pump(tester, db, initialDate: yesterday);

    await tester.tap(_seg(1, 10));
    await _openSheetPump(tester);

    expect(find.byType(LogEntrySheet), findsOneWidget);
    expect(find.text('Edit Entry'), findsOneWidget,
        reason: 'existing-entry tap is the unchanged edit path');

    await _teardown(tester, db);
  });
}
