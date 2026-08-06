import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/shell/app_shell.dart';
import 'package:chronoplan/features/tasks/intention_task_sheet.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/intention_tasks_provider.dart';

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

/// Minimal shell + single route hosting the task sheet directly, so a real
/// WidgetsBindingObserver-driven lifecycle event exercises the exact
/// production wiring (AppShell), not a stand-in.
Widget _harness(AppDatabase db, DateTime initialDay) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const IntentionTaskSheet()),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      currentDayProvider.overrideWith((ref) => initialDay),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
    'resident app resumed after midnight: tasks roll forward and reappear '
    '(this is the exact bug — must fail before the fix, pass after)',
    (tester) async {
      final db = await tester.runAsync(() async {
        final d = AppDatabase(NativeDatabase.memory());
        await d.getSettings();
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        await d.intentionTasksDao.addTask(yesterday, 'task 1');
        await d.intentionTasksDao.addTask(yesterday, 'task 2 - flagged');
        await d.intentionTasksDao.addTask(yesterday, 'task 3');
        final rows = await d.select(d.intentionTasks).get();
        final toFlag = rows.firstWhere((t) => t.label.contains('flagged'));
        await d.intentionTasksDao.setFlag(yesterday, toFlag.id);
        return d;
      });

      final yesterdayKey = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
      final todayKey = _dayKey(DateTime.now());

      // Simulate: app was opened yesterday and has stayed resident —
      // currentDayProvider is still bound to yesterday's key.
      await tester.pumpWidget(_harness(db!, yesterdayKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Sanity check on the simulated starting state.
      expect(find.text('task 1'), findsOneWidget);
      expect(find.text('task 2 - flagged'), findsOneWidget);
      expect(find.text('task 3'), findsOneWidget);

      // Fire a genuine OS-level resume — AppShell's WidgetsBindingObserver
      // must notice the real clock has moved to a new day.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // The bug (unfixed): dayTasksProvider stays bound to yesterdayKey,
      // which rollForward never touches once it's not "today" anymore ->
      // the list silently goes empty. The fix: currentDayProvider flips to
      // todayKey, rollForward(todayKey) runs, tasks reappear under today.
      expect(find.text('task 1'), findsOneWidget);
      expect(find.text('task 2 - flagged'), findsOneWidget);
      expect(find.text('task 3'), findsOneWidget);

      final rowsAfter = await tester.runAsync(() => db.select(db.intentionTasks).get());
      expect(rowsAfter!.every((t) => t.date == todayKey), isTrue,
          reason: 'carried tasks must now be dated today, not yesterday');

      await tester.runAsync(() => db.close());
    },
  );

  testWidgets('cold start after midnight: no lifecycle event needed at all',
      (tester) async {
    final db = await tester.runAsync(() async {
      final d = AppDatabase(NativeDatabase.memory());
      await d.getSettings();
      await d.intentionTasksDao.addTask(DateTime.now(), 'fresh today task');
      return d;
    });

    // No currentDayProvider override: a cold start reads its default
    // initializer, normalizeDay(DateTime.now()), same as production.
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (context, state) => const IntentionTaskSheet()),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db!)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('fresh today task'), findsOneWidget);
    await tester.runAsync(() => db.close());
  });

  testWidgets(
      'same-day resume does not disturb the list or spuriously re-roll',
      (tester) async {
    final db = await tester.runAsync(() async {
      final d = AppDatabase(NativeDatabase.memory());
      await d.getSettings();
      await d.intentionTasksDao.addTask(DateTime.now(), 'today task');
      return d;
    });

    final todayKey = _dayKey(DateTime.now());
    await tester.pumpWidget(_harness(db!, todayKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('today task'), findsOneWidget);

    // Foreground/background within the same day. Flutter's lifecycle state
    // machine requires the full real transition sequence (resumed ->
    // inactive -> hidden -> paused, then back paused -> hidden -> inactive
    // -> resumed), same as an actual OS backgrounding/foregrounding.
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

    // Still there, untouched — the currentDayProvider key didn't change so
    // dayTasksProvider(todayKey)/rollForwardProvider(todayKey) are the same
    // cached provider instances as before, not re-created.
    expect(find.text('today task'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(IntentionTaskSheet)),
    );
    expect(container.read(currentDayProvider), todayKey);

    await tester.runAsync(() => db.close());
  });
}
