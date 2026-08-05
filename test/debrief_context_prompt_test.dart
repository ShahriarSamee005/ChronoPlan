import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/debrief/debrief_screen.dart';

IntentionTask _task({
  required int id,
  required String label,
  bool isFlagged = false,
  int sortOrder = 1,
}) =>
    IntentionTask(
      id: id,
      label: label,
      isDone: false,
      isFlagged: isFlagged,
      sortOrder: sortOrder,
      date: DateTime.now(),
    );

void main() {
  test('focus line uses the flagged task, not intention.intention', () {
    final prompt = buildDebriefContextPrompt(
      entries: const [],
      cats: const [],
      routine: const [],
      intention: null, // daily_intentions text is no longer consulted
      tasks: [
        _task(id: 1, label: 'unflagged first task', sortOrder: 1),
        _task(id: 2, label: 'the flagged one', isFlagged: true, sortOrder: 2),
      ],
      doneTaskCount: 1,
      totalTaskCount: 3,
    );

    expect(prompt, contains("Today's focus: the flagged one"));
    expect(prompt, isNot(contains('unflagged first task')));
    expect(prompt, contains('Tasks: completed 1 of 3 today'));
  });

  test('falls back to the #1 (lowest sortOrder) task when none flagged', () {
    final prompt = buildDebriefContextPrompt(
      entries: const [],
      cats: const [],
      routine: const [],
      intention: null,
      tasks: [
        _task(id: 1, label: 'lowest sort order task', sortOrder: 1),
        _task(id: 2, label: 'later task', sortOrder: 2),
      ],
      doneTaskCount: 0,
      totalTaskCount: 2,
    );

    expect(prompt, contains("Today's focus: lowest sort order task"));
    expect(prompt, isNot(contains('later task')));
  });

  test('empty string / "Not set" when there are no tasks at all', () {
    final prompt = buildDebriefContextPrompt(
      entries: const [],
      cats: const [],
      routine: const [],
      intention: null,
      tasks: const [],
      doneTaskCount: 0,
      totalTaskCount: 0,
    );

    expect(prompt, contains("Today's focus: Not set"));
    expect(prompt, contains('Tasks: completed 0 of 0 today'));
  });

  test('verdict_positive line is untouched by the task-list change', () {
    final positive = buildDebriefContextPrompt(
      entries: const [],
      cats: const [],
      routine: const [],
      intention: DailyIntention(
        id: 1,
        intention: 'legacy text — no longer read for the focus line',
        date: DateTime.now(),
        wasReflected: false,
        verdictPositive: true,
        createdAt: DateTime.now(),
      ),
      tasks: const [],
      doneTaskCount: 0,
      totalTaskCount: 0,
    );
    expect(positive, contains('Day verdict: Good day (👍)'));
    // The old intention text column must not leak into the new focus line.
    expect(positive, isNot(contains('legacy text')));

    final notRated = buildDebriefContextPrompt(
      entries: const [],
      cats: const [],
      routine: const [],
      intention: null,
      tasks: const [],
      doneTaskCount: 0,
      totalTaskCount: 0,
    );
    expect(notRated, contains('Day verdict: Not yet rated'));
  });
}
