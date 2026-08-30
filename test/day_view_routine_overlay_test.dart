import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/day_view/day_view_screen.dart';
import 'package:chronoplan/features/log_entry/log_entry_sheet.dart';
import 'package:chronoplan/providers/database_provider.dart';

// Render-tree tests for the Day View routine overlay edge. Everything about the
// surface, the in-memory DB, the bounded pumping (the screen runs a one-minute
// Timer.periodic, so pumpAndSettle never terminates) and the teardown recipe is
// lifted from day_view_row_layout_test.dart, so the two suites behave the same.
//
// Clock strategy: the widget calls planRoutineEdges(now: DateTime.now()), so
// rather than fight the clock we pin the shown date. PAST/verdict cases use
// YESTERDAY (every slot is already past); the NEUTRAL case uses TOMORROW (no
// slot has happened yet). Verdict/neutral slots use dayOfWeek == 0 (every day)
// so the day-of-week filter never interferes; the filter is tested on its own.

const double _surfaceW = 800.0;
const double _surfaceH = 1800.0;

// Verdict edge colours, read straight from _verdictToEdge in production so the
// assertions track the source rather than hard-coded guesses.
const Color _green = Colors.greenAccent;
const Color _amber = Colors.amberAccent;
final Color _red = Colors.redAccent.withValues(alpha: 0.7);

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

/// The one-minute now-line ticker means `pumpAndSettle` never returns; pump a
/// bounded number of frames instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Tear the tree down so the ticker is cancelled, let the real loop flush the
/// Drift stream cancellation, then close — `db.close()` hangs otherwise.
Future<void> _teardown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {});
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(() => db.close());
}

Future<int> _category(
  WidgetTester tester,
  AppDatabase db, {
  required int colorValue,
  String name = 'Focus',
}) =>
    tester
        .runAsync(() => db.categoriesDao.insertCategory(
              CategoriesCompanion.insert(name: name, colorValue: colorValue),
            ))
        .then((v) => v!);

Future<int> _slot(
  WidgetTester tester,
  AppDatabase db, {
  required int dayOfWeek,
  required int startHour,
  int durationHours = 1,
  int? categoryId,
  bool isActive = true,
}) =>
    tester
        .runAsync(() => db.routineSlotsDao.insertSlot(
              RoutineSlotsCompanion.insert(
                categoryId: Value(categoryId),
                dayOfWeek: dayOfWeek,
                startHour: startHour,
                durationHours: Value(durationHours),
                isActive: Value(isActive),
              ),
            ))
        .then((v) => v!);

Future<void> _log(
  WidgetTester tester,
  AppDatabase db, {
  required DateTime start,
  required DateTime end,
  required String description,
  int? categoryId,
}) =>
    tester.runAsync(() => db.logEntriesDao.insertRetroactive(
          startTime: start,
          endTime: end,
          categoryId: categoryId,
          description: description,
        ));

Finder _edge(int hour) => find.byKey(ValueKey('routine_edge_$hour'));

Finder _accent(int hour) => find.byKey(ValueKey('routine_accent_$hour'));

Finder _seg(int entryId, int hour, {int lane = 0}) =>
    find.byKey(ValueKey('seg_${entryId}_${hour}_$lane'));

/// The verdict-coloured accent bar's colour + width for [hour]. The accent lives
/// in its own thin left bar layered over the rounded base block, so the verdict
/// is read here rather than off the block's (now uniform) border.
({Color color, double width}) _accentEdge(WidgetTester tester, int hour) {
  final container = tester.widget<Container>(_accent(hour));
  final decoration = container.decoration as BoxDecoration;
  return (color: decoration.color!, width: (container.constraints!).maxWidth);
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));
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

  testWidgets('1. an active every-day slot draws edges only on its hours',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    // Every-day slot spanning 09:00–11:00 (hours 9 and 10).
    await _slot(tester, db,
        dayOfWeek: 0, startHour: 9, durationHours: 2, categoryId: cat);
    await _pump(tester, db, initialDate: yesterday);

    expect(_edge(9), findsOneWidget);
    expect(_edge(10), findsOneWidget);
    // Uncovered hours carry no edge at all.
    expect(_edge(8), findsNothing);
    expect(_edge(11), findsNothing);
    expect(_edge(3), findsNothing);
    expect(_edge(15), findsNothing);

    await _teardown(tester, db);
  });

  testWidgets('2. an inactive slot draws nothing', (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db,
        dayOfWeek: 0,
        startHour: 9,
        durationHours: 2,
        categoryId: cat,
        isActive: false);
    await _pump(tester, db, initialDate: yesterday);

    for (var h = 0; h < 24; h++) {
      expect(_edge(h), findsNothing, reason: 'inactive slot: no edge at hour $h');
    }

    await _teardown(tester, db);
  });

  testWidgets('3. the day-of-week filter hides non-matching slots',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    // The shown day is yesterday; compute its weekday so this never depends on
    // which real weekday the suite runs on.
    final shownWeekday = yesterday.weekday; // 1..7
    final otherWeekday = shownWeekday % 7 + 1; // a different weekday, 1..7

    // Non-matching slot at 03:00–04:00 — should be filtered out entirely.
    await _slot(tester, db,
        dayOfWeek: otherWeekday, startHour: 3, durationHours: 1, categoryId: cat);
    // Control slot matching the shown weekday at 08:00–09:00.
    await _slot(tester, db,
        dayOfWeek: shownWeekday, startHour: 8, durationHours: 1, categoryId: cat);
    await _pump(tester, db, initialDate: yesterday);

    expect(_edge(3), findsNothing, reason: 'wrong-weekday slot is filtered out');
    expect(_edge(8), findsOneWidget, reason: 'matching-weekday slot draws');

    await _teardown(tester, db);
  });

  testWidgets('4. past + full coverage + category match → green 3.5px',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db,
        dayOfWeek: 0, startHour: 9, durationHours: 2, categoryId: cat);
    // Logs fully cover 09:00–11:00 with the slot's own category.
    await _log(tester, db,
        start: at(yesterday, 9),
        end: at(yesterday, 11),
        description: 'Focus block',
        categoryId: cat);
    await _pump(tester, db, initialDate: yesterday);

    for (final h in [9, 10]) {
      final side = _accentEdge(tester, h);
      expect(side.color, _green, reason: 'hour $h should be green');
      expect(side.width, closeTo(3.5, 0.01), reason: 'hour $h width');
    }

    await _teardown(tester, db);
  });

  testWidgets('5. past + full coverage + wrong category → amber 3.5px',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db,
        dayOfWeek: 0, startHour: 9, durationHours: 2, categoryId: cat);
    // Fully covered, but the log carries no category → no match → amber.
    await _log(tester, db,
        start: at(yesterday, 9),
        end: at(yesterday, 11),
        description: 'Uncategorised',
        categoryId: null);
    await _pump(tester, db, initialDate: yesterday);

    for (final h in [9, 10]) {
      final side = _accentEdge(tester, h);
      expect(side.color, _amber, reason: 'hour $h should be amber');
      expect(side.width, closeTo(3.5, 0.01), reason: 'hour $h width');
    }

    await _teardown(tester, db);
  });

  testWidgets('6. past + partial coverage (0.10–0.75) → amber 3.5px',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db,
        dayOfWeek: 0, startHour: 9, durationHours: 2, categoryId: cat);
    // 30 of 120 minutes covered = 0.25 coverage, matching category or not.
    await _log(tester, db,
        start: at(yesterday, 9),
        end: at(yesterday, 9, 30),
        description: 'Partial',
        categoryId: cat);
    await _pump(tester, db, initialDate: yesterday);

    for (final h in [9, 10]) {
      final side = _accentEdge(tester, h);
      expect(side.color, _amber, reason: 'hour $h should be amber');
      expect(side.width, closeTo(3.5, 0.01), reason: 'hour $h width');
    }

    await _teardown(tester, db);
  });

  testWidgets('7. past + near-zero coverage → red 3.5px', (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db,
        dayOfWeek: 0, startHour: 9, durationHours: 2, categoryId: cat);
    // No logs at all → coverage 0 → red.
    await _pump(tester, db, initialDate: yesterday);

    for (final h in [9, 10]) {
      final side = _accentEdge(tester, h);
      expect(side.color, _red, reason: 'hour $h should be red');
      expect(side.width, closeTo(3.5, 0.01), reason: 'hour $h width');
    }

    await _teardown(tester, db);
  });

  testWidgets('8. not past → neutral 1.5px regardless of logs', (tester) async {
    final db = await _memoryDb(tester);
    const colorValue = 0xFF4E9AF1;
    final cat = await _category(tester, db, colorValue: colorValue);
    await _slot(tester, db,
        dayOfWeek: 0, startHour: 9, durationHours: 2, categoryId: cat);
    // Fully covered with a matching category — would be green if it were past.
    await _log(tester, db,
        start: at(tomorrow, 9),
        end: at(tomorrow, 11),
        description: 'Future block',
        categoryId: cat);
    await _pump(tester, db, initialDate: tomorrow);

    for (final h in [9, 10]) {
      final side = _accentEdge(tester, h);
      expect(side.width, closeTo(1.5, 0.01), reason: 'hour $h neutral width');
      // Neutral tints the category colour; it is none of the verdict accents.
      expect(side.color, isNot(_green));
      expect(side.color, isNot(_amber));
      expect(side.color, isNot(_red));
      expect(side.color, const Color(colorValue).withValues(alpha: 0.22),
          reason: 'hour $h neutral is the faded category colour');
    }

    await _teardown(tester, db);
  });

  testWidgets('9. a 3-hour slot shows one verdict colour across all 3 rows',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db,
        dayOfWeek: 0, startHour: 9, durationHours: 3, categoryId: cat);
    // Fully covered 09:00–12:00 with the slot's category → green on 9, 10, 11.
    await _log(tester, db,
        start: at(yesterday, 9),
        end: at(yesterday, 12),
        description: 'Long focus',
        categoryId: cat);
    await _pump(tester, db, initialDate: yesterday);

    for (final h in [9, 10, 11]) {
      final side = _accentEdge(tester, h);
      expect(side.color, _green, reason: 'hour $h should be green');
      expect(side.width, closeTo(3.5, 0.01), reason: 'hour $h width');
    }
    expect(_edge(12), findsNothing, reason: 'slot ends before hour 12');

    await _teardown(tester, db);
  });

  testWidgets('10. the edge sits behind the segment and does not steal taps',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    // A slot AND an overlapping log in the same hour (10:00–11:00).
    await _slot(tester, db,
        dayOfWeek: 0, startHour: 10, durationHours: 1, categoryId: cat);
    await _log(tester, db,
        start: at(yesterday, 10),
        end: at(yesterday, 11),
        description: 'Tap me',
        categoryId: cat);
    await _pump(tester, db, initialDate: yesterday);

    // Both are present in the same hour…
    expect(_edge(10), findsOneWidget);
    expect(_seg(1, 10), findsOneWidget);

    // …and the tap reaches the segment, not the IgnorePointer-wrapped edge.
    await tester.tap(_seg(1, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LogEntrySheet), findsOneWidget);

    await _teardown(tester, db);
  });
}
