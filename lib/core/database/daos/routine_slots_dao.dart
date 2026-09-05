import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/routine_slots_table.dart';

part 'routine_slots_dao.g.dart';

@DriftAccessor(tables: [RoutineSlots])
class RoutineSlotsDao extends DatabaseAccessor<AppDatabase>
    with _$RoutineSlotsDaoMixin {
  RoutineSlotsDao(super.db);

  /// Watch slots for a specific day-of-week (1=Mon … 7=Sun).
  /// Slots with dayOfWeek == 0 apply every day and are always included.
  Stream<List<RoutineSlot>> watchForDay(int dayOfWeek) =>
      (select(routineSlots)
            ..where((s) =>
                s.isActive.equals(true) &
                (s.dayOfWeek.equals(dayOfWeek) | s.dayOfWeek.equals(0)))
            ..orderBy([(s) => OrderingTerm(expression: s.startHour)]))
          .watch();

  Future<List<RoutineSlot>> getForDay(int dayOfWeek) =>
      (select(routineSlots)
            ..where((s) =>
                s.isActive.equals(true) &
                (s.dayOfWeek.equals(dayOfWeek) | s.dayOfWeek.equals(0)))
            ..orderBy([(s) => OrderingTerm(expression: s.startHour)]))
          .get();

  /// Total number of routine slots (active or not) — analytics counter only.
  Future<int> countAll() async {
    final query = selectOnly(routineSlots)
      ..addColumns([routineSlots.id.count()]);
    final row = await query.getSingle();
    return row.read(routineSlots.id.count()) ?? 0;
  }

  Future<int> insertSlot(RoutineSlotsCompanion entry) =>
      into(routineSlots).insert(entry);

  Future<void> updateSlot(RoutineSlotsCompanion entry) =>
      (update(routineSlots)..where((s) => s.id.equals(entry.id.value)))
          .write(entry);

  Future<void> deleteSlot(int id) =>
      (delete(routineSlots)..where((s) => s.id.equals(id))).go();

  Future<void> setActive(int id, {required bool active}) =>
      (update(routineSlots)..where((s) => s.id.equals(id)))
          .write(RoutineSlotsCompanion(isActive: Value(active)));

  Stream<List<RoutineSlot>> watchAll() =>
      (select(routineSlots)
            ..orderBy([
              (s) => OrderingTerm(expression: s.dayOfWeek),
              (s) => OrderingTerm(expression: s.startHour),
            ]))
          .watch();

  /// Copy all slots for [fromDay] to each day in [toDays].
  /// Only copies day-specific slots (dayOfWeek == fromDay), not "every day" ones.
  Future<void> copyDaySlots(int fromDay, List<int> toDays) async {
    final source = await (select(routineSlots)
          ..where((s) =>
              s.dayOfWeek.equals(fromDay) & s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm(expression: s.startHour)]))
        .get();

    for (final targetDay in toDays) {
      for (final slot in source) {
        await into(routineSlots).insert(RoutineSlotsCompanion.insert(
          categoryId: Value(slot.categoryId),
          label: Value(slot.label),
          dayOfWeek: targetDay,
          startHour: slot.startHour,
          durationHours: Value(slot.durationHours),
          isActive: const Value(true),
        ));
      }
    }
  }
}
