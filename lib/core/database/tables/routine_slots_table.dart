import 'package:drift/drift.dart';

class RoutineSlots extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().nullable()();
  TextColumn get label => text().withDefault(const Constant(''))();
  // 1=Mon … 7=Sun; 0=applies every day
  IntColumn get dayOfWeek => integer()();
  IntColumn get startHour => integer()(); // 0–23
  // User drags bottom edge to extend; stored as whole hours
  IntColumn get durationHours =>
      integer().withDefault(const Constant(1))();
  BoolColumn get isActive =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  TextColumn get userId => text().nullable()();
  TextColumn get syncId => text().nullable()();
}
