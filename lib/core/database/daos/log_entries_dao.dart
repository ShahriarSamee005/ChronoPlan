import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables/log_entries_table.dart';

part 'log_entries_dao.g.dart';

@DriftAccessor(tables: [LogEntries])
class LogEntriesDao extends DatabaseAccessor<AppDatabase>
    with _$LogEntriesDaoMixin {
  LogEntriesDao(super.db);

  static const _uuid = Uuid();

  // ── Queries ─────────────────────────────────────────────────────────────

  Stream<List<LogEntry>> watchForDay(DateTime date) {
    final start = _dayStart(date);
    final end = start.add(const Duration(days: 1));
    return (select(logEntries)
          ..where((e) =>
              e.startTime.isBiggerOrEqualValue(start) &
              e.startTime.isSmallerThanValue(end))
          ..orderBy([(e) => OrderingTerm(expression: e.startTime)]))
        .watch();
  }

  Future<List<LogEntry>> getForDay(DateTime date) {
    final start = _dayStart(date);
    final end = start.add(const Duration(days: 1));
    return (select(logEntries)
          ..where((e) =>
              e.startTime.isBiggerOrEqualValue(start) &
              e.startTime.isSmallerThanValue(end))
          ..orderBy([(e) => OrderingTerm(expression: e.startTime)]))
        .get();
  }

  Future<List<LogEntry>> getAll() =>
      (select(logEntries)
            ..orderBy([(e) => OrderingTerm(expression: e.startTime)]))
          .get();

  Future<List<LogEntry>> getForWeek(DateTime weekStart) {
    final end = weekStart.add(const Duration(days: 7));
    return (select(logEntries)
          ..where((e) =>
              e.startTime.isBiggerOrEqualValue(weekStart) &
              e.startTime.isSmallerThanValue(end))
          ..orderBy([(e) => OrderingTerm(expression: e.startTime)]))
        .get();
  }

  // ── Inserts ──────────────────────────────────────────────────────────────

  /// Real-time entry — inserted directly, never split or blocked.
  Future<int> insertRealTime({
    required DateTime startTime,
    required DateTime endTime,
    required int? categoryId,
    required String description,
  }) =>
      into(logEntries).insert(LogEntriesCompanion.insert(
        startTime: startTime,
        endTime: endTime,
        categoryId: Value(categoryId),
        description: Value(description),
        isRealTime: const Value(true),
        syncId: Value(_uuid.v4()),
      ));

  /// Retroactive entry — auto-splits around any existing real-time entries
  /// in the requested window, filling only the empty gaps.
  /// Returns the IDs of rows created (empty list = window fully blocked).
  Future<List<int>> insertRetroactive({
    required DateTime startTime,
    required DateTime endTime,
    required int? categoryId,
    required String description,
  }) async {
    final blockers = await _realTimeBlockers(startTime, endTime);
    final gaps = _gaps(startTime, endTime, blockers);
    if (gaps.isEmpty) return [];

    final ids = <int>[];
    for (final (gapStart, gapEnd) in gaps) {
      final id = await into(logEntries).insert(LogEntriesCompanion.insert(
        startTime: gapStart,
        endTime: gapEnd,
        categoryId: Value(categoryId),
        description: Value(description),
        isRealTime: const Value(false),
        syncId: Value(_uuid.v4()),
      ));
      ids.add(id);
    }
    return ids;
  }

  // ── Mutations ────────────────────────────────────────────────────────────

  Future<void> updateEntry(LogEntriesCompanion entry) =>
      (update(logEntries)..where((e) => e.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteEntry(int id) =>
      (delete(logEntries)..where((e) => e.id.equals(id))).go();

  // ── Helpers ──────────────────────────────────────────────────────────────

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<List<LogEntry>> _realTimeBlockers(
    DateTime start,
    DateTime end,
  ) =>
      (select(logEntries)
            ..where((e) =>
                e.isRealTime.equals(true) &
                e.startTime.isSmallerThanValue(end) &
                e.endTime.isBiggerThanValue(start))
            ..orderBy([(e) => OrderingTerm(expression: e.startTime)]))
          .get();

  /// Compute free gaps in [start, end] around the sorted blocker list.
  List<(DateTime, DateTime)> _gaps(
    DateTime start,
    DateTime end,
    List<LogEntry> blockers,
  ) {
    final gaps = <(DateTime, DateTime)>[];
    var cursor = start;
    for (final b in blockers) {
      if (cursor.isBefore(b.startTime)) gaps.add((cursor, b.startTime));
      if (b.endTime.isAfter(cursor)) cursor = b.endTime;
    }
    if (cursor.isBefore(end)) gaps.add((cursor, end));
    return gaps;
  }
}
