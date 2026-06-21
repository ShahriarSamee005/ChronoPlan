import 'package:drift/drift.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  IntColumn get colorValue => integer()(); // 0xFFRRGGBB
  BoolColumn get isArchived =>
      boolean().withDefault(const Constant(false))();
  // System categories (e.g. Sleep) cannot be deleted
  BoolColumn get isSystem =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  TextColumn get userId => text().nullable()();
  TextColumn get syncId => text().nullable()(); // UUID for Supabase sync
}
