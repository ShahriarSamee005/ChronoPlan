import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/dashboard/widgets/daily_intention_card.dart';
import 'package:chronoplan/providers/database_provider.dart';

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

void main() {
  test(
      'done tasks never carry, not-done tasks roll forward with flag/order '
      'preserved, removed tasks never carry', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings();

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final today = DateTime.now();
    final todayKey = _dayKey(today);

    await db.intentionTasksDao.addTask(yesterday, 'task A - will be done');
    await db.intentionTasksDao.addTask(yesterday, 'task B - flagged, not done');
    await db.intentionTasksDao.addTask(yesterday, 'task C - not done, not flagged');
    await db.intentionTasksDao.addTask(yesterday, 'task D - will be removed');

    final all = await db.select(db.intentionTasks).get();
    final taskA = all.firstWhere((t) => t.label.startsWith('task A'));
    final taskB = all.firstWhere((t) => t.label.startsWith('task B'));
    final taskD = all.firstWhere((t) => t.label.startsWith('task D'));

    await db.intentionTasksDao.setDone(taskA.id); // done: must not carry
    await db.intentionTasksDao.setFlag(yesterday, taskB.id);
    await db.intentionTasksDao.removeTask(taskD.id); // removed: must never carry

    // Simulate "reopen tomorrow": the day-load roll-forward call.
    await db.intentionTasksDao.rollForward(todayKey);

    final todayTasks = await db.intentionTasksDao.watchForDay(todayKey).first;
    expect(todayTasks.length, 2);
    expect(
      todayTasks.map((t) => t.label).toSet(),
      {'task B - flagged, not done', 'task C - not done, not flagged'},
    );
    expect(todayTasks.every((t) => t.date == todayKey), isTrue,
        reason: 'carried tasks must be dated today, not yesterday');

    final flaggedToday = todayTasks.firstWhere((t) => t.label.startsWith('task B'));
    expect(flaggedToday.isFlagged, isTrue,
        reason: 'flag state must survive the carry-over');
    // sortOrder preserved (global monotonic, never reset) — B was inserted
    // before C, so B keeps the lower sortOrder after rolling forward too.
    final carriedC = todayTasks.firstWhere((t) => t.label.startsWith('task C'));
    expect(flaggedToday.sortOrder, lessThan(carriedC.sortOrder));

    final rowsAfter = await db.select(db.intentionTasks).get();

    // Done task did NOT carry: still dated yesterday, still done.
    final doneRow = rowsAfter.firstWhere((t) => t.label.startsWith('task A'));
    expect(doneRow.date, _dayKey(yesterday));
    expect(doneRow.isDone, isTrue);

    // Removed task never reappears anywhere.
    expect(rowsAfter.any((t) => t.label.startsWith('task D')), isFalse);
    expect(rowsAfter.length, 3); // A (done), B, C — D hard-deleted

    await db.close();
  });

  testWidgets(
      'flagged carried-over task surfaces on the dashboard card on reopen '
      '(no sheet-open required)', (tester) async {
    final db = await tester.runAsync(() async {
      final d = AppDatabase(NativeDatabase.memory());
      await d.getSettings();
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await d.intentionTasksDao.addTask(yesterday, 'stale not-flagged');
      await d.intentionTasksDao.addTask(yesterday, 'carried, flagged');
      final rows = await d.select(d.intentionTasks).get();
      final toFlag = rows.firstWhere((t) => t.label == 'carried, flagged');
      await d.intentionTasksDao.setFlag(yesterday, toFlag.id);
      return d;
    });

    // Pump ONLY the dashboard card — never opening the task sheet — to
    // confirm the card itself triggers roll-forward on load.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db!)],
        child: const MaterialApp(home: Scaffold(body: DailyIntentionCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('carried, flagged'), findsOneWidget);

    final today = DateTime.now();
    final rows = await tester.runAsync(() => db.select(db.intentionTasks).get());
    expect(rows!.every((t) => t.date == _dayKey(today)), isTrue);

    await tester.runAsync(() => db.close());
  });
}
