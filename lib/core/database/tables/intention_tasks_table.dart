import 'package:drift/drift.dart';

class IntentionTasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  DateTimeColumn get doneAt => dateTime().nullable()();
  BoolColumn get isFlagged => boolean().withDefault(const Constant(false))();
  // Global monotonic order — never reset per day, so carry-over keeps stable ordering.
  IntColumn get sortOrder => integer()();
  // Stored as midnight local time for the day (date-only semantics)
  DateTimeColumn get date => dateTime()();
}
