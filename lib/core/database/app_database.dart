import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/categories_table.dart';
import 'tables/daily_intentions_table.dart';
import 'tables/dismissed_suggestions_table.dart';
import 'tables/log_entries_table.dart';
import 'tables/routine_slots_table.dart';
import 'tables/user_settings_table.dart';
import 'daos/categories_dao.dart';
import 'daos/dismissed_suggestions_dao.dart';
import 'daos/intentions_dao.dart';
import 'daos/log_entries_dao.dart';
import 'daos/routine_slots_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Categories,
    LogEntries,
    RoutineSlots,
    DailyIntentions,
    UserSettings,
    DismissedSuggestions,
  ],
  daos: [
    CategoriesDao,
    DismissedSuggestionsDao,
    LogEntriesDao,
    RoutineSlotsDao,
    IntentionsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Seed default categories and the single settings row
          await categoriesDao.insertDefaults();
          await into(userSettings).insert(UserSettingsCompanion.insert());
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Add verdict column — raw SQL works before build_runner regenerates
            await m.database.customStatement(
              'ALTER TABLE daily_intentions '
              'ADD COLUMN verdict_positive INTEGER',
            );
          }
          if (from < 3) {
            // Seed the Screen Time system category for existing installs.
            // New installs get it from insertDefaults() via onCreate.
            final existing =
                await categoriesDao.findByName('Screen Time');
            if (existing == null) {
              await categoriesDao.insertCategory(
                CategoriesCompanion.insert(
                  name: 'Screen Time',
                  colorValue: 0xFF5E60CE,
                  isSystem: const Value(true),
                ),
              );
            }
          }
          if (from < 4) {
            // Add the dismissed_suggestions table for Phase 2 usage suggestions.
            await m.createTable(dismissedSuggestions);
          }
        },
      );

  // ── Settings helpers (single-row table) ──────────────────────────────────

  Future<UserSetting> getSettings() =>
      (select(userSettings)..limit(1)).getSingle();

  Stream<UserSetting> watchSettings() =>
      (select(userSettings)..limit(1)).watchSingle();

  Future<void> updateSettings(UserSettingsCompanion patch) =>
      (update(userSettings)..where((s) => s.id.equals(1))).write(patch);
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'chronoplan.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
