import 'package:drift/drift.dart';

class DailyIntentions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get intention => text()();
  // Stored as midnight local time for the day (date-only semantics)
  DateTimeColumn get date => dateTime()();
  BoolColumn get wasReflected =>
      boolean().withDefault(const Constant(false))();
  // null = not yet rated; true = good day; false = bad day
  BoolColumn get verdictPositive => boolean().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  TextColumn get userId => text().nullable()();
  TextColumn get syncId => text().nullable()();
}
