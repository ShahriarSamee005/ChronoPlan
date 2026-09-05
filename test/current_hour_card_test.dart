import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/dashboard/widgets/current_hour_card.dart';
import 'package:chronoplan/providers/database_provider.dart';

Future<AppDatabase> _memoryDb(WidgetTester tester) {
  return tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings(); // seeds the singleton settings row
    return db;
  }).then((v) => v!);
}

/// Seeds a routine slot covering the current hour on every weekday.
Future<void> _seedSlotCoveringNow(
  WidgetTester tester,
  AppDatabase db, {
  required String label,
  bool isActive = true,
}) {
  final hour = DateTime.now().hour;
  return tester.runAsync(() async {
    await db.routineSlotsDao.insertSlot(RoutineSlotsCompanion.insert(
      dayOfWeek: 0, // every day — avoids weekday arithmetic in the test
      startHour: hour,
      durationHours: const Value(1),
      label: Value(label),
      isActive: Value(isActive),
    ));
  });
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: Scaffold(body: CurrentHourCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// CurrentHourCard and _LiveClock each arm an uncancellable `Future.delayed` to
/// the next minute boundary in initState; nothing disposes those. Tearing the
/// tree down first and then running the clock out lets each callback hit its
/// `if (!mounted) return` without arming a periodic Timer — otherwise the test
/// trips "A Timer is still pending after the widget tree was disposed." Mirrors
/// dashboard_launch_test.dart's teardown.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 61));
}

void main() {
  testWidgets('routine slot covering the current hour -> its name renders',
      (tester) async {
    final db = await _memoryDb(tester);
    await _seedSlotCoveringNow(tester, db, label: 'Deep Work');
    await _pump(tester, db);

    expect(find.text('Deep Work'), findsOneWidget);
    expect(find.text('— nothing planned'), findsNothing);

    await _teardown(tester);
    await tester.runAsync(() => db.close());
  });

  testWidgets('no applicable slot -> "nothing planned" renders',
      (tester) async {
    final db = await _memoryDb(tester);
    await _pump(tester, db);

    expect(find.text('— nothing planned'), findsOneWidget);

    await _teardown(tester);
    await tester.runAsync(() => db.close());
  });

  testWidgets('inactive slot covering the current hour -> "nothing planned"',
      (tester) async {
    final db = await _memoryDb(tester);
    await _seedSlotCoveringNow(tester, db, label: 'Deep Work', isActive: false);
    await _pump(tester, db);

    expect(find.text('— nothing planned'), findsOneWidget);
    expect(find.text('Deep Work'), findsNothing);

    await _teardown(tester);
    await tester.runAsync(() => db.close());
  });

  testWidgets(
      'replace proof: a log entry covering now with no routine slot shows '
      '"nothing planned", never the log description', (tester) async {
    final db = await _memoryDb(tester);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await db.logEntriesDao.insertRealTime(
        startTime: now.subtract(const Duration(minutes: 30)),
        endTime: now.add(const Duration(minutes: 30)),
        categoryId: null,
        description: 'Logged Thing',
      );
    });
    await _pump(tester, db);

    // The card no longer reads logged entries at all.
    expect(find.text('Logged Thing'), findsNothing);
    expect(find.text('— nothing planned'), findsOneWidget);

    await _teardown(tester);
    await tester.runAsync(() => db.close());
  });
}
