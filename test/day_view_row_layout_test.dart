import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/theme/glass_card.dart';
import 'package:chronoplan/features/day_view/day_view_screen.dart';
import 'package:chronoplan/features/log_entry/log_entry_sheet.dart';
import 'package:chronoplan/providers/database_provider.dart';

// Row geometry for the Phase-2 Day View. The surface is sized so all 24 hour
// rows fit without scrolling, which keeps every assertion deterministic
// regardless of what time the suite happens to run at.
//
// As in the other widget tests here, raw DB work goes through tester.runAsync —
// stream reads don't progress inside the fake-async zone otherwise.

const double _laneHeight = 52.0;
const double _surfaceW = 800.0;
const double _surfaceH = 1800.0;

/// Timeline width = surface − 52 px hour gutter − 8 px right gutter.
const double _trackW = _surfaceW - 52 - 8;

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

/// The screen runs a one-minute `Timer.periodic` for the now-line, so
/// `pumpAndSettle` never terminates — it advances fake time, the ticker fires,
/// that schedules another frame, forever. Bounded pumps instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Tears the tree down so the screen's one-minute ticker is cancelled (a live
/// Timer fails the test), then lets the real event loop flush the Drift stream
/// cancellation before closing — `db.close()` blocks forever on a subscription
/// that is still unwinding.
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

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  DateTime at(DateTime day, int h, [int m = 0]) =>
      DateTime(day.year, day.month, day.day, h, m);

  setUp(() {
    // Sized in setUp so every test starts from the same surface.
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views.first;
    view.physicalSize = const Size(_surfaceW, _surfaceH);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('every hour renders a row, empty hours included', (tester) async {
    final db = await _memoryDb(tester);
    await _pump(tester, db);

    for (final h in [0, 6, 12, 18, 23]) {
      expect(find.text('${h.toString().padLeft(2, '0')}:00'), findsOneWidget,
          reason: 'hour $h must render even with nothing logged');
    }
    await _teardown(tester, db);
  });

  testWidgets('a 60-min log fills the row, a 30-min log fills half',
      (tester) async {
    final db = await _memoryDb(tester);
    await _log(tester, db,
        start: at(today, 9), end: at(today, 10), description: 'Full hour');
    await _log(tester, db,
        start: at(today, 11), end: at(today, 11, 30), description: 'Half hour');
    await _pump(tester, db);

    expect(tester.getSize(_seg(1, 9)).width, closeTo(_trackW, 0.5));
    expect(tester.getSize(_seg(2, 11)).width, closeTo(_trackW / 2, 0.5));
    // The half-hour block starts flush left, on the hour.
    expect(tester.getTopLeft(_seg(2, 11)).dx,
        closeTo(tester.getTopLeft(_seg(1, 9)).dx, 0.5));

    // The coloured card must fill its slot — left to itself it shrinks to the
    // width of its label, which paints a chip and shrinks the tap target.
    for (final entryId in [1, 2]) {
      final slot = entryId == 1 ? _seg(1, 9) : _seg(2, 11);
      final card = find.descendant(
        of: slot,
        matching: find.byType(GlassCard),
      );
      expect(tester.getSize(card), tester.getSize(slot),
          reason: 'entry $entryId card should fill its segment box');
    }

    await _teardown(tester, db);
  });

  testWidgets('a 15-min block keeps true width and shows its label',
      (tester) async {
    final db = await _memoryDb(tester);
    await _log(tester, db,
        start: at(today, 8), end: at(today, 8, 15), description: 'Standup');
    await _pump(tester, db);

    // Well above the 48 px floor, so the width stays truthful.
    expect(tester.getSize(_seg(1, 8)).width, closeTo(_trackW / 4, 0.5));
    expect(find.text('Standup'), findsOneWidget);

    await _teardown(tester, db);
  });

  testWidgets('a tiny sliver is floored to a tappable width, not clipped out',
      (tester) async {
    final db = await _memoryDb(tester);
    // 2 minutes = ~24 px at true width, below the 48 px floor.
    await _log(tester, db,
        start: at(today, 7, 58), end: at(today, 8), description: 'Blip');
    await _pump(tester, db);

    final size = tester.getSize(_seg(1, 7));
    expect(size.width, 48.0, reason: 'floored to the minimum tap target');
    // Floored at the very end of the hour → shifted back to stay inside.
    final left = tester.getTopLeft(_seg(1, 7)).dx;
    expect(left + size.width, lessThanOrEqualTo(_surfaceW - 8 + 0.5));

    await _teardown(tester, db);
  });

  testWidgets("last night's sleep is one continuous bar, labelled once",
      (tester) async {
    final db = await _memoryDb(tester);
    await _log(tester, db,
        start: at(yesterday, 23), end: at(today, 6, 45), description: 'Sleep');
    await _pump(tester, db);

    // Present in every row from 00:00 through 06:00 — no gap after midnight.
    for (var h = 0; h <= 6; h++) {
      expect(_seg(1, h), findsOneWidget, reason: 'sleep missing in hour $h');
    }
    expect(_seg(1, 7), findsNothing);

    // Full-width through 05:00, then the 45-minute tail.
    for (var h = 0; h <= 5; h++) {
      expect(tester.getSize(_seg(1, h)).width, closeTo(_trackW, 0.5),
          reason: 'hour $h should span the whole row');
    }
    expect(tester.getSize(_seg(1, 6)).width, closeTo(_trackW * 0.75, 0.5));

    // Labelled on its first visible hour only.
    expect(find.text('Sleep'), findsOneWidget);

    await _teardown(tester, db);
  });

  testWidgets('overlapping entries stack into lanes and grow the row',
      (tester) async {
    final db = await _memoryDb(tester);
    await _log(tester, db,
        start: at(today, 14), end: at(today, 15), description: 'Meeting');
    await _log(tester, db,
        start: at(today, 14, 20),
        end: at(today, 14, 50),
        description: 'Side task');
    await _pump(tester, db);

    final a = _seg(1, 14);
    final b = _seg(2, 14, lane: 1);
    expect(a, findsOneWidget);
    expect(b, findsOneWidget);

    // Second lane sits exactly one lane lower; neither is clipped away.
    expect(tester.getTopLeft(b).dy - tester.getTopLeft(a).dy,
        closeTo(_laneHeight, 0.5));
    expect(tester.getSize(a).height, _laneHeight - 4);
    expect(tester.getSize(b).height, _laneHeight - 4);

    // The 14:00 row is twice as tall as a single-lane row: the 15:00 label
    // sits two lanes below the 14:00 one.
    final gap = tester.getTopLeft(find.text('15:00')).dy -
        tester.getTopLeft(find.text('14:00')).dy;
    expect(gap, closeTo(_laneHeight * 2, 0.5));

    await _teardown(tester, db);
  });

  testWidgets('tapping a segment opens the edit sheet', (tester) async {
    final db = await _memoryDb(tester);
    await _log(tester, db,
        start: at(today, 10), end: at(today, 11), description: 'Deep work');
    await _pump(tester, db);

    await tester.tap(_seg(1, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LogEntrySheet), findsOneWidget);

    await _teardown(tester, db);
  });

  testWidgets('swiping one segment removes every segment of that entry',
      (tester) async {
    final db = await _memoryDb(tester);
    await _log(tester, db,
        start: at(today, 2), end: at(today, 5), description: 'Long block');
    await _pump(tester, db);

    expect(_seg(1, 2), findsOneWidget);
    expect(_seg(1, 3), findsOneWidget);
    expect(_seg(1, 4), findsOneWidget);

    await tester.drag(_seg(1, 3), const Offset(-600, 0));
    await _settle(tester);

    for (var h = 2; h <= 4; h++) {
      expect(_seg(1, h), findsNothing,
          reason: 'hour $h segment should vanish with the entry');
    }

    await _teardown(tester, db);
  });

  testWidgets('the now-line sits in the current hour at the right offset',
      (tester) async {
    final db = await _memoryDb(tester);
    await _pump(tester, db);

    final line = find.byKey(const Key('now_line'));
    expect(line, findsOneWidget, reason: 'exactly one row carries the now-line');

    final clock = DateTime.now();

    // Horizontal: spans the whole block area, flush with the hour gutter.
    expect(tester.getSize(line).width, closeTo(_trackW, 0.5));
    expect(tester.getTopLeft(line).dx, closeTo(52, 0.5));

    // It belongs to the current hour's row, and sits `minute/60` of the way
    // down it. Nothing is logged here, so the row is a single lane tall.
    final hourLabel = find.text('${clock.hour.toString().padLeft(2, '0')}:00');
    final rowTop = tester.getTopLeft(hourLabel).dy - 2; // label's 2 px padding
    var expectedY = clock.minute / 60 * _laneHeight;
    // Same end-of-hour clamp the widget applies, so :59 stays inside the row.
    if (expectedY > _laneHeight - 1.5) expectedY = _laneHeight - 1.5;
    expect(tester.getTopLeft(line).dy, closeTo(rowTop + expectedY, 2.0));

    await _teardown(tester, db);
  });

  testWidgets('a past day shows no now-line', (tester) async {
    final db = await _memoryDb(tester);
    await _pump(tester, db, initialDate: yesterday);

    expect(find.byKey(const Key('now_line')), findsNothing);

    await _teardown(tester, db);
  });
}
