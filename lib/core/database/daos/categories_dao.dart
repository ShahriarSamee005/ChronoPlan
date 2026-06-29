import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/categories_table.dart';

part 'categories_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Stream<List<Category>> watchAll() => (select(categories)
        ..where((c) => c.isArchived.equals(false))
        ..orderBy([(c) => OrderingTerm(expression: c.name)]))
      .watch();

  Future<List<Category>> getAll() => (select(categories)
        ..where((c) => c.isArchived.equals(false))
        ..orderBy([(c) => OrderingTerm(expression: c.name)]))
      .get();

  Future<Category?> getById(int id) =>
      (select(categories)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Future<Category?> findByName(String name) =>
      (select(categories)..where((c) => c.name.equals(name)))
          .getSingleOrNull();

  Future<int> insertCategory(CategoriesCompanion entry) =>
      into(categories).insert(entry);

  Future<void> updateCategory(CategoriesCompanion entry) =>
      (update(categories)..where((c) => c.id.equals(entry.id.value)))
          .write(entry);

  Future<void> archive(int id) =>
      (update(categories)..where((c) => c.id.equals(id)))
          .write(const CategoriesCompanion(isArchived: Value(true)));

  Future<void> insertDefaults() async {
    // 10 curated default categories — colorblind-aware palette
    const defaults = [
      ('Work', 0xFF4E9AF1, false),
      ('Exercise', 0xFF6BCB77, false),
      ('Sleep', 0xFF1A1040, true), // system: excluded from productivity score
      ('Entertainment', 0xFFFF6B6B, false),
      ('Social', 0xFFC77DFF, false),
      ('Learning', 0xFFFFD93D, false),
      ('Meals', 0xFFFF9F43, false),
      ('Personal Care', 0xFF4ECDC4, false),
      ('Travel', 0xFF74B9FF, false),
      ('Admin', 0xFF55EFC4, false),
      ('Screen Time', 0xFF5E60CE, true), // system: usage-stats-derived entries
    ];
    for (final (name, color, isSystem) in defaults) {
      await into(categories).insert(CategoriesCompanion.insert(
        name: name,
        colorValue: color,
        isSystem: Value(isSystem),
      ));
    }
  }
}
