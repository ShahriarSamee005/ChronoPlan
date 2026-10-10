import 'dart:ffi';

import 'package:chronoplan/core/backup/backup_serializer.dart';
import 'package:chronoplan/core/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

/// DB-backed coverage for the backup read layer (`AppDatabase.readAllForBackup`)
/// against a REAL in-memory Drift database. Uses the same sqlite3 load the other
/// DB-backed tests use on this Windows box.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('fresh DB: valid map, all 8 table keys, exactly one settings row', () async {
    final data = await db.readAllForBackup();
    final map = buildBackupMapFrom(data, schemaVersion: db.schemaVersion);
    final tables = map['tables'] as Map<String, dynamic>;

    // All 8 keys present, every value a List — no null, no crash.
    expect(tables.keys.toSet(), {
      kTableCategories,
      kTableLogEntries,
      kTableRoutineSlots,
      kTableDailyIntentions,
      kTableUserSettings,
      kTableDismissedSuggestions,
      kTableDismissedCarves,
      kTableIntentionTasks,
    });
    for (final v in tables.values) {
      expect(v, isA<List>());
    }

    // onCreate seeds exactly one user_settings row...
    expect((tables[kTableUserSettings] as List).length, 1);
    // ...and the default categories (see CategoriesDao.insertDefaults),
    // so categories is NOT empty on a fresh DB.
    expect((tables[kTableCategories] as List), isNotEmpty);
    // The genuinely user-driven tables start empty.
    expect(tables[kTableLogEntries], isEmpty);
    expect(tables[kTableRoutineSlots], isEmpty);
    expect(tables[kTableDailyIntentions], isEmpty);
    expect(tables[kTableDismissedSuggestions], isEmpty);
    expect(tables[kTableDismissedCarves], isEmpty);
    expect(tables[kTableIntentionTasks], isEmpty);
  });

  test('seeded rows via the real DAOs all appear in the output', () async {
    final catId = await db.categoriesDao.insertCategory(
      CategoriesCompanion.insert(name: 'Focus', colorValue: 0xFF112233),
    );
    final start = DateTime.utc(2026, 5, 6, 9);
    await db.logEntriesDao.insertRealTime(
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      categoryId: catId,
      description: 'sprint',
    );
    await db.routineSlotsDao.insertSlot(
      RoutineSlotsCompanion.insert(
        categoryId: Value(catId),
        dayOfWeek: 1,
        startHour: 9,
      ),
    );

    final data = await db.readAllForBackup();
    final tables =
        buildBackupMapFrom(data, schemaVersion: db.schemaVersion)['tables']
            as Map<String, dynamic>;

    final cats = (tables[kTableCategories] as List).cast<Map>();
    expect(cats.any((c) => c['name'] == 'Focus'), isTrue);

    final logs = (tables[kTableLogEntries] as List).cast<Map>();
    expect(logs.length, 1);
    expect(logs.single['description'], 'sprint');
    expect(logs.single['startTime'], start.millisecondsSinceEpoch);

    final slots = (tables[kTableRoutineSlots] as List).cast<Map>();
    expect(slots.length, 1);
    expect(slots.single['categoryId'], catId);
  });

  test('archived categories are still captured (getAll would drop them)', () async {
    // Backups must not silently lose archived categories. readAllForBackup uses
    // an unfiltered select, unlike CategoriesDao.getAll().
    await db.categoriesDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'Archived',
        colorValue: 0xFF445566,
        isArchived: const Value(true),
      ),
    );

    final data = await db.readAllForBackup();
    final cats =
        (buildBackupMapFrom(data, schemaVersion: db.schemaVersion)['tables']
                as Map<String, dynamic>)[kTableCategories] as List;

    expect(cats.cast<Map>().any((c) => c['name'] == 'Archived'), isTrue);
    // Sanity: the filtered DAO path would NOT return it.
    final viaDao = await db.categoriesDao.getAll();
    expect(viaDao.any((c) => c.name == 'Archived'), isFalse);
  });

  test('schemaVersion in output equals the DB schemaVersion, read dynamically',
      () async {
    final data = await db.readAllForBackup();
    final map = buildBackupMapFrom(data, schemaVersion: db.schemaVersion);

    // Reads the DB's real value — catches a hardcoded constant drifting from it.
    expect(map['schemaVersion'], db.schemaVersion);
    expect(map['schemaVersion'], 9); // current schema, update when bumped
  });
}
