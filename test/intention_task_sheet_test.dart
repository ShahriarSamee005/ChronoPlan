import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/theme/glass_card.dart';
import 'package:chronoplan/features/tasks/intention_task_sheet.dart';
import 'package:chronoplan/providers/database_provider.dart';

// Raw DB work (stream reads especially) doesn't progress inside testWidgets'
// fake-async zone unless run via tester.runAsync — otherwise it hangs
// indefinitely with the VM idle. All direct DAO/db calls below go through it.

Future<AppDatabase> _memoryDb(WidgetTester tester) {
  return tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings(); // force onCreate
    return db;
  }).then((v) => v!);
}

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: Scaffold(body: IntentionTaskSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sheet chrome matches log-entry sheet conventions',
      (tester) async {
    final db = await _memoryDb(tester);
    await _pump(tester, db);

    final card = tester.widget<GlassCard>(find.byType(GlassCard).first);
    expect(card.borderRadius, 28);
    expect(card.opacity, 0.20);
    expect(card.blurSigma, 16);

    expect(find.byType(Padding), findsWidgets); // bottom viewInsets padding
    await tester.runAsync(() => db.close());
  });

  testWidgets('adding tasks respects the 10-task cap with a visible hint',
      (tester) async {
    final db = await _memoryDb(tester);
    final today = DateTime.now();
    await tester.runAsync(() async {
      for (var i = 0; i < 9; i++) {
        await db.intentionTasksDao.addTask(today, 'task $i');
      }
    });
    await _pump(tester, db);

    // 10th via the UI. Avoid pumpAndSettle here: a focused TextField's
    // blinking cursor keeps scheduling frames forever, so pumpAndSettle
    // (no default timeout) hangs indefinitely. Bounded pumps instead.
    await tester.enterText(find.byType(TextField), 'task 9');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('task 9'), findsOneWidget);

    // At cap: field disabled, hint visible, no silent 11th add.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    expect(find.text('10 max'), findsOneWidget);

    final tasks = await tester
        .runAsync(() => db.intentionTasksDao.watchForDay(today).first);
    expect(tasks!.length, 10);
    await tester.runAsync(() => db.close());
  });

  testWidgets('swipe Done hides the task; swipe Remove deletes it',
      (tester) async {
    final db = await _memoryDb(tester);
    final today = DateTime.now();
    await tester.runAsync(() async {
      await db.intentionTasksDao.addTask(today, 'finish report');
      await db.intentionTasksDao.addTask(today, 'call dentist');
    });
    await _pump(tester, db);

    expect(find.text('finish report'), findsOneWidget);
    expect(find.text('call dentist'), findsOneWidget);

    // Swipe first row open, tap Done. Bounded pumps after the tap: the row
    // gets removed from the stream-driven list while its Slidable is still
    // closing, which can leave pumpAndSettle waiting on frames forever.
    await tester.drag(find.text('finish report'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('finish report'), findsNothing);

    final doneTask = await tester.runAsync(() async {
      final rows = await db.select(db.intentionTasks).get();
      return rows.firstWhere((t) => t.label == 'finish report');
    });
    expect(doneTask!.isDone, isTrue);
    expect(doneTask.doneAt, isNotNull);

    // Swipe remaining row open, tap Remove.
    await tester.drag(find.text('call dentist'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('call dentist'), findsNothing);

    final remaining = await tester.runAsync(() => db.select(db.intentionTasks).get());
    expect(remaining!.any((t) => t.label == 'call dentist'), isFalse); // hard-deleted
    expect(remaining.length, 1); // only the (done) 'finish report' row remains
    await tester.runAsync(() => db.close());
  });

  testWidgets('flagging a task clears any previously flagged one',
      (tester) async {
    final db = await _memoryDb(tester);
    final today = DateTime.now();
    await tester.runAsync(() async {
      await db.intentionTasksDao.addTask(today, 'alpha');
      await db.intentionTasksDao.addTask(today, 'beta');
    });
    await _pump(tester, db);

    final flagButtons = find.byIcon(Icons.flag_outlined);
    expect(flagButtons, findsNWidgets(2));

    await tester.tap(flagButtons.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);

    final rows = await tester.runAsync(() => db.select(db.intentionTasks).get());
    expect(rows!.where((t) => t.isFlagged).length, 1);
    expect(rows.firstWhere((t) => t.isFlagged).label, 'beta');
    await tester.runAsync(() => db.close());
  });

  testWidgets('roll-forward brings yesterday\'s open task onto today',
      (tester) async {
    final db = await _memoryDb(tester);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await tester.runAsync(() => db.intentionTasksDao.addTask(yesterday, 'carried task'));
    await _pump(tester, db);

    expect(find.text('carried task'), findsOneWidget);
    final today = DateTime.now();
    final dayKey = DateTime(today.year, today.month, today.day);
    final rows = await tester.runAsync(() => db.select(db.intentionTasks).get());
    expect(rows!.first.date, dayKey);
    await tester.runAsync(() => db.close());
  });
}
