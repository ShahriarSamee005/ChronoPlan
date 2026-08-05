import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/intention_tasks_table.dart';

part 'intention_tasks_dao.g.dart';

enum AddTaskResult { added, dayFull }

const kMaxTasksPerDay = 10;

@DriftAccessor(tables: [IntentionTasks])
class IntentionTasksDao extends DatabaseAccessor<AppDatabase>
    with _$IntentionTasksDaoMixin {
  IntentionTasksDao(super.db);

  /// Not-done tasks for the day, in insertion (sortOrder) order.
  Stream<List<IntentionTask>> watchForDay(DateTime date) {
    final day = _dayKey(date);
    return (select(intentionTasks)
          ..where((t) => t.date.equals(day) & t.isDone.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<AddTaskResult> addTask(DateTime date, String text) async {
    final day = _dayKey(date);
    final count = await _countNotDoneForDay(day);
    if (count >= kMaxTasksPerDay) return AddTaskResult.dayFull;

    final maxSort = await _maxSortOrder();
    await into(intentionTasks).insert(IntentionTasksCompanion.insert(
      label: text,
      date: day,
      sortOrder: maxSort + 1,
    ));
    return AddTaskResult.added;
  }

  Future<void> setDone(int id) =>
      (update(intentionTasks)..where((t) => t.id.equals(id))).write(
        IntentionTasksCompanion(
          isDone: const Value(true),
          doneAt: Value(DateTime.now()),
        ),
      );

  Future<void> removeTask(int id) =>
      (delete(intentionTasks)..where((t) => t.id.equals(id))).go();

  Future<void> setFlag(DateTime date, int id) async {
    final day = _dayKey(date);
    await transaction(() async {
      await (update(intentionTasks)..where((t) => t.date.equals(day))).write(
        const IntentionTasksCompanion(isFlagged: Value(false)),
      );
      await (update(intentionTasks)..where((t) => t.id.equals(id))).write(
        const IntentionTasksCompanion(isFlagged: Value(true)),
      );
    });
  }

  Future<int> countDoneForDay(DateTime date) async {
    final day = _dayKey(date);
    final query = selectOnly(intentionTasks)
      ..addColumns([intentionTasks.id.count()])
      ..where(intentionTasks.date.equals(day) & intentionTasks.isDone.equals(true));
    final row = await query.getSingle();
    return row.read(intentionTasks.id.count()) ?? 0;
  }

  Future<int> countTotalForDay(DateTime date) async {
    final day = _dayKey(date);
    final query = selectOnly(intentionTasks)
      ..addColumns([intentionTasks.id.count()])
      ..where(intentionTasks.date.equals(day));
    final row = await query.getSingle();
    return row.read(intentionTasks.id.count()) ?? 0;
  }

  /// Rolls any not-done task with date < today forward onto today.
  /// Preserves isFlagged. Call once when today's list loads.
  Future<void> rollForward(DateTime today) async {
    final day = _dayKey(today);
    await transaction(() async {
      await (update(intentionTasks)
            ..where((t) => t.isDone.equals(false) & t.date.isSmallerThanValue(day)))
          .write(IntentionTasksCompanion(date: Value(day)));
    });
  }

  Future<int> _countNotDoneForDay(DateTime day) async {
    final query = selectOnly(intentionTasks)
      ..addColumns([intentionTasks.id.count()])
      ..where(intentionTasks.date.equals(day) & intentionTasks.isDone.equals(false));
    final row = await query.getSingle();
    return row.read(intentionTasks.id.count()) ?? 0;
  }

  Future<int> _maxSortOrder() async {
    final query = selectOnly(intentionTasks)
      ..addColumns([intentionTasks.sortOrder.max()]);
    final row = await query.getSingle();
    return row.read(intentionTasks.sortOrder.max()) ?? 0;
  }

  /// Midnight local time — used as a date-only key.
  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);
}
