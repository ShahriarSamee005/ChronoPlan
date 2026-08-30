import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/routine/routine_screen.dart';
import 'package:chronoplan/providers/database_provider.dart';

// Row-geometry tests for the rebuilt Routine screen, which now draws through the
// shared HourTimeline. The harness mirrors day_view_row_layout_test.dart (an
// in-memory Drift DB forced through onCreate), but the Routine screen has NO
// one-minute ticker, so plain pumpAndSettle terminates.
//
// The screen is weekday-keyed: it selects DateTime.now().weekday on start, so
// every slot here is created with dayOfWeek == 0 (every day) to stay visible
// whatever real weekday the suite runs on.

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

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const RoutineScreen()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _teardown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {});
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(() => db.close());
}

Future<int> _category(WidgetTester tester, AppDatabase db,
        {required int colorValue, String name = 'Focus'}) =>
    tester
        .runAsync(() => db.categoriesDao.insertCategory(
              CategoriesCompanion.insert(name: name, colorValue: colorValue),
            ))
        .then((v) => v!);

Future<int> _slot(
  WidgetTester tester,
  AppDatabase db, {
  required int startHour,
  int durationHours = 1,
  int? categoryId,
  String label = '',
}) =>
    tester
        .runAsync(() => db.routineSlotsDao.insertSlot(
              RoutineSlotsCompanion.insert(
                categoryId: Value(categoryId),
                label: Value(label),
                dayOfWeek: 0, // every day → always shown
                startHour: startHour,
                durationHours: Value(durationHours),
              ),
            ))
        .then((v) => v!);

Finder _seg(int slotId, int hour, {int lane = 0}) =>
    find.byKey(ValueKey('seg_${slotId}_${hour}_$lane'));

void main() {
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

  testWidgets('a 1h slot fills its row width', (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db, startHour: 9, categoryId: cat, label: 'Focus');
    await _pump(tester, db);

    expect(_seg(1, 9), findsOneWidget);
    expect(tester.getSize(_seg(1, 9)).width, closeTo(_trackW, 0.5));

    await _teardown(tester, db);
  });

  testWidgets('a multi-hour slot is one continuous bar across its rows',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db,
        startHour: 9, durationHours: 3, categoryId: cat, label: 'Long');
    await _pump(tester, db);

    // Present in 9, 10, 11 at full width; absent at 12.
    for (final h in [9, 10, 11]) {
      expect(_seg(1, h), findsOneWidget, reason: 'hour $h should carry the bar');
      expect(tester.getSize(_seg(1, h)).width, closeTo(_trackW, 0.5));
    }
    expect(_seg(1, 12), findsNothing);

    // Labelled once, on its first hour only.
    expect(find.text('Long'), findsOneWidget);

    await _teardown(tester, db);
  });

  testWidgets('two overlapping slots lane-stack and grow the row',
      (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db, startHour: 14, categoryId: cat, label: 'A');
    await _slot(tester, db, startHour: 14, categoryId: cat, label: 'B');
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

    await _teardown(tester, db);
  });

  testWidgets('tapping a segment opens the slot editor', (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db, startHour: 10, categoryId: cat, label: 'Edit me');
    await _pump(tester, db);

    await tester.tap(_seg(1, 10));
    await tester.pumpAndSettle();

    // The edit sheet shows its "Edit slot" title.
    expect(find.text('Edit slot'), findsOneWidget);

    await _teardown(tester, db);
  });

  testWidgets('swiping a segment fires the delete', (tester) async {
    final db = await _memoryDb(tester);
    final cat = await _category(tester, db, colorValue: 0xFF4E9AF1);
    await _slot(tester, db, startHour: 3, categoryId: cat, label: 'Bye');
    await _pump(tester, db);

    expect(_seg(1, 3), findsOneWidget);
    await tester.drag(_seg(1, 3), const Offset(-600, 0));
    await tester.pumpAndSettle();

    // The dismissed slot leaves the tree via the _pendingDeleteIds guard.
    expect(_seg(1, 3), findsNothing);

    await _teardown(tester, db);
  });

  testWidgets('tapping an empty hour opens the create sheet', (tester) async {
    final db = await _memoryDb(tester);
    await _category(tester, db, colorValue: 0xFF4E9AF1);
    // No slots at all → every hour is empty and tappable.
    await _pump(tester, db);

    // The empty-hour GestureDetector fills the track (not the gutter label), so
    // tap inside hour 8's track: same row as the "08:00" label, but to its right.
    final labelY = tester.getCenter(find.text('08:00')).dy;
    await tester.tapAt(Offset(400, labelY));
    await tester.pumpAndSettle();

    expect(find.text('New slot'), findsOneWidget);

    await _teardown(tester, db);
  });
}
