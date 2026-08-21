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

  Future<LogEntry?> getById(int id) =>
      (select(logEntries)..where((e) => e.id.equals(id))).getSingleOrNull();

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

  /// Retroactive entry — auto-splits around any existing blocking entries in
  /// the requested window, filling only the empty gaps.
  ///
  /// Returns the rows created plus how much of the request was satisfied, so
  /// callers can tell FULL from PARTIAL from NONE:
  ///   • `writtenMinutes == requestedMinutes` → the whole window was written
  ///   • `0 < writtenMinutes < requestedMinutes` → it slotted around blockers
  ///   • `writtenMinutes == 0` (and `ids` empty) → fully blocked, nothing written
  ///
  /// [isUsageDerived] tags the row as OS-screen-time origin (confirm/carve).
  /// Defaults to false so the manual-log path is unaffected.
  ///
  /// [avoidUsageDerived] additionally treats existing screen-time rows as
  /// blockers, so a manual log fills around confirmed screen time instead of
  /// stacking on top of it. Defaults to false: every other caller keeps today's
  /// behavior, where only real-time entries block.
  Future<({List<int> ids, int requestedMinutes, int writtenMinutes})>
      insertRetroactive({
    required DateTime startTime,
    required DateTime endTime,
    required int? categoryId,
    required String description,
    bool isUsageDerived = false,
    bool avoidUsageDerived = false,
  }) async {
    final requestedMinutes = endTime.difference(startTime).inMinutes;

    final blockers = await _blockers(
      startTime,
      endTime,
      avoidUsageDerived: avoidUsageDerived,
    );
    final gaps = _gaps(startTime, endTime, blockers);
    if (gaps.isEmpty) {
      return (
        ids: const <int>[],
        requestedMinutes: requestedMinutes,
        writtenMinutes: 0,
      );
    }

    final ids = <int>[];
    var writtenMinutes = 0;
    for (final (gapStart, gapEnd) in gaps) {
      final id = await into(logEntries).insert(LogEntriesCompanion.insert(
        startTime: gapStart,
        endTime: gapEnd,
        categoryId: Value(categoryId),
        description: Value(description),
        isRealTime: const Value(false),
        isUsageDerived: Value(isUsageDerived),
        syncId: Value(_uuid.v4()),
      ));
      ids.add(id);
      writtenMinutes += gapEnd.difference(gapStart).inMinutes;
    }
    return (
      ids: ids,
      requestedMinutes: requestedMinutes,
      writtenMinutes: writtenMinutes,
    );
  }

  // ── Mutations ────────────────────────────────────────────────────────────

  Future<void> updateEntry(LogEntriesCompanion entry) =>
      (update(logEntries)..where((e) => e.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteEntry(int id) =>
      (delete(logEntries)..where((e) => e.id.equals(id))).go();

  // ── Helpers ──────────────────────────────────────────────────────────────

  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Existing entries that block part of [start, end].
  ///
  /// Real-time entries are always sacred. [avoidUsageDerived] widens the set to
  /// include OS screen-time rows as well — parenthesized so the OR groups
  /// before the overlap terms are ANDed on.
  Future<List<LogEntry>> _blockers(
    DateTime start,
    DateTime end, {
    required bool avoidUsageDerived,
  }) =>
      (select(logEntries)
            ..where((e) {
              final blocks = avoidUsageDerived
                  ? (e.isRealTime.equals(true) |
                      e.isUsageDerived.equals(true))
                  : e.isRealTime.equals(true);
              return blocks &
                  e.startTime.isSmallerThanValue(end) &
                  e.endTime.isBiggerThanValue(start);
            })
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
