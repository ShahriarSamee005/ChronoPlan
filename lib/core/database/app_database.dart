import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'tables/categories_table.dart';
import 'tables/daily_intentions_table.dart';
import 'tables/dismissed_carves_table.dart';
import 'tables/dismissed_suggestions_table.dart';
import 'tables/intention_tasks_table.dart';
import 'tables/log_entries_table.dart';
import 'tables/routine_slots_table.dart';
import 'tables/user_settings_table.dart';
import 'daos/categories_dao.dart';
import 'daos/dismissed_carves_dao.dart';
import 'daos/dismissed_suggestions_dao.dart';
import 'daos/intention_tasks_dao.dart';
import 'daos/intentions_dao.dart';
import 'daos/log_entries_dao.dart';
import 'daos/routine_slots_dao.dart';
import '../backup/backup_serializer.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Categories,
    LogEntries,
    RoutineSlots,
    DailyIntentions,
    UserSettings,
    DismissedSuggestions,
    DismissedCarves,
    IntentionTasks,
  ],
  daos: [
    CategoriesDao,
    DismissedCarvesDao,
    DismissedSuggestionsDao,
    LogEntriesDao,
    RoutineSlotsDao,
    IntentionsDao,
    IntentionTasksDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 9;

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
            // Add the dismissed_suggestions table for Phase 2a usage suggestions.
            await m.createTable(dismissedSuggestions);
          }
          if (from < 5) {
            // Add the dismissed_carves table for Phase 2b carve-proposal dismissals.
            await m.createTable(dismissedCarves);
          }
          if (from < 6) {
            // Add the intention_tasks table for the daily to-do list.
            await m.createTable(intentionTasks);
          }
          if (from < 7) {
            // Add is_usage_derived to log_entries so reconciliation can tell
            // OS-derived screen-time rows apart from user log entries.
            await m.addColumn(logEntries, logEntries.isUsageDerived);
          }
          if (from < 8) {
            // Add battery_exemption_asked so the one-time Doze-exemption prompt
            // on first sleep-mode enable is shown exactly once. Pure additive
            // column with a default — no existing data touched.
            await m.addColumn(userSettings, userSettings.batteryExemptionAsked);
          }
          if (from < 9) {
            // Give categories, routine_slots, daily_intentions and
            // intention_tasks a stable UUID syncId for Supabase sync. The first
            // three already have a (never-populated) nullable column; only
            // intention_tasks needs the column added. Then backfill a fresh,
            // unique UUID into every existing row that has a NULL syncId.
            //
            // ATOMICITY: on native sqlite3 drift uses a NoTransactionDelegate
            // and does NOT wrap onUpgrade in a transaction, so this step wraps
            // itself in one explicit transaction. A failure mid-backfill rolls
            // back BOTH the column add and every UPDATE, leaving a clean v8
            // state; schemaVersion is only persisted after onUpgrade returns
            // normally, so the step retries cleanly from v8 on the next open.
            await transaction(() async {
              await m.addColumn(intentionTasks, intentionTasks.syncId);
              await _backfillSyncIdsForV9();
            });
          }
        },
      );

  /// Backfills a unique UUID into every NULL `syncId` across the four in-scope
  /// tables. One fresh uuid per row; existing non-null syncIds (e.g.
  /// log_entries, or any already set) are never touched. Touches only the
  /// syncId column — no row added, removed, or otherwise modified. Empty tables
  /// are a no-op. Must run inside the v8->v9 migration transaction.
  Future<void> _backfillSyncIdsForV9() async {
    const uuid = Uuid();

    final catRows =
        await (select(categories)..where((c) => c.syncId.isNull())).get();
    for (final r in catRows) {
      await (update(categories)..where((c) => c.id.equals(r.id)))
          .write(CategoriesCompanion(syncId: Value(uuid.v4())));
    }

    final slotRows =
        await (select(routineSlots)..where((s) => s.syncId.isNull())).get();
    for (final r in slotRows) {
      await (update(routineSlots)..where((s) => s.id.equals(r.id)))
          .write(RoutineSlotsCompanion(syncId: Value(uuid.v4())));
    }

    final intentionRows =
        await (select(dailyIntentions)..where((i) => i.syncId.isNull())).get();
    for (final r in intentionRows) {
      await (update(dailyIntentions)..where((i) => i.id.equals(r.id)))
          .write(DailyIntentionsCompanion(syncId: Value(uuid.v4())));
    }

    final taskRows =
        await (select(intentionTasks)..where((t) => t.syncId.isNull())).get();
    for (final r in taskRows) {
      await (update(intentionTasks)..where((t) => t.id.equals(r.id)))
          .write(IntentionTasksCompanion(syncId: Value(uuid.v4())));
    }
  }

  // ── Settings helpers (single-row table) ──────────────────────────────────

  Future<UserSetting> getSettings() =>
      (select(userSettings)..limit(1)).getSingle();

  Stream<UserSetting> watchSettings() =>
      (select(userSettings)..limit(1)).watchSingle();

  Future<void> updateSettings(UserSettingsCompanion patch) =>
      (update(userSettings)..where((s) => s.id.equals(1))).write(patch);

  // ── Backup read layer ─────────────────────────────────────────────────────

  /// Reads EVERY row of EVERY table for a local backup export. Read-only.
  ///
  /// Uses unfiltered `select(table).get()` per table rather than the existing
  /// DAO `getAll()` helpers on purpose: `CategoriesDao.getAll()` excludes
  /// archived categories, which a complete backup must still capture (restore
  /// would otherwise lose them). This method is the single feed for the
  /// serializer — see [buildBackupMapFrom].
  Future<BackupData> readAllForBackup() async {
    return BackupData(
      categories: await select(categories).get(),
      logEntries: await select(logEntries).get(),
      routineSlots: await select(routineSlots).get(),
      dailyIntentions: await select(dailyIntentions).get(),
      userSettings: await select(userSettings).get(),
      dismissedSuggestions: await select(dismissedSuggestions).get(),
      dismissedCarves: await select(dismissedCarves).get(),
      intentionTasks: await select(intentionTasks).get(),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'chronoplan.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
