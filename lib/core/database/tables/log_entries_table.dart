import 'package:drift/drift.dart';

class LogEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get description =>
      text().withDefault(const Constant(''))();
  // Nullable FK → categories.id (enforced at app layer)
  IntColumn get categoryId => integer().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  // Real-time entries are sacred: never overwritten by retroactive ones
  BoolColumn get isRealTime =>
      boolean().withDefault(const Constant(false))();
  // True when AI parsed the description into this entry
  BoolColumn get isAiParsed =>
      boolean().withDefault(const Constant(false))();
  // True when this row came from an OS screen-time confirm/carve, not a user
  // log. Used by reconciliation to keep suggestions/missing-hours user-driven.
  BoolColumn get isUsageDerived =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  TextColumn get userId => text().nullable()();
  TextColumn get syncId => text().nullable()();
}
