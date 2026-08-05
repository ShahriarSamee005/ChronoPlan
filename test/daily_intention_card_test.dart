import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/dashboard/widgets/daily_intention_card.dart';
import 'package:chronoplan/features/tasks/intention_task_sheet.dart';
import 'package:chronoplan/providers/database_provider.dart';

Future<AppDatabase> _memoryDb(WidgetTester tester) {
  return tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings();
    return db;
  }).then((v) => v!);
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: Scaffold(body: DailyIntentionCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fresh day, no tasks -> card shows the empty prompt',
      (tester) async {
    final db = await _memoryDb(tester);
    await _pump(tester, db);

    expect(
      find.text("What's the one thing that would make today a win?"),
      findsOneWidget,
    );
    await tester.runAsync(() => db.close());
  });

  testWidgets('add + flag a task -> card shows the flagged task\'s text',
      (tester) async {
    final db = await _memoryDb(tester);
    final today = DateTime.now();
    await tester.runAsync(() async {
      await db.intentionTasksDao.addTask(today, 'first task');
      await db.intentionTasksDao.addTask(today, 'second task');
      final rows = await db.select(db.intentionTasks).get();
      final second = rows.firstWhere((t) => t.label == 'second task');
      await db.intentionTasksDao.setFlag(today, second.id);
    });
    await _pump(tester, db);

    expect(find.text('second task'), findsOneWidget);
    expect(find.text('first task'), findsNothing);
    await tester.runAsync(() => db.close());
  });

  testWidgets(
      'no flag, tasks present -> card shows the #1 (lowest sortOrder) task',
      (tester) async {
    final db = await _memoryDb(tester);
    final today = DateTime.now();
    await tester.runAsync(() async {
      await db.intentionTasksDao.addTask(today, 'first task');
      await db.intentionTasksDao.addTask(today, 'second task');
    });
    await _pump(tester, db);

    expect(find.text('first task'), findsOneWidget);
    expect(find.text('second task'), findsNothing);
    await tester.runAsync(() => db.close());
  });

  testWidgets('tapping the card opens the task sheet', (tester) async {
    final db = await _memoryDb(tester);
    await _pump(tester, db);

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(IntentionTaskSheet), findsOneWidget);
    await tester.runAsync(() => db.close());
  });
}
