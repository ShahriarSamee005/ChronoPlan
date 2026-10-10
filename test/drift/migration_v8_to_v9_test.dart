// ---------------------------------------------------------------------------
// THE PROOF for Backup Phase 2b: the v8 -> v9 syncId backfill migration.
//
// This opens a REAL v8 database (via the Phase 2a SchemaVerifier harness),
// seeds real rows with NULL syncId (v8 has no way to set it) plus a log_entries
// row that already carries a non-null syncId, runs the ACTUAL onUpgrade to v9,
// and inspects the resulting v9 database. Nothing here is faked — it exercises
// the migration that will run on a tester's populated phone.
//
// Regenerating the schema helpers these tests depend on: see the command block
// in migration_harness_test.dart. The sqlite3 DLL path below is the same
// machine-specific path every DB-backed test in this repo uses.
// ---------------------------------------------------------------------------

import 'dart:ffi';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

import 'generated/schema.dart';

// A fixed, recognisable syncId pre-seeded onto log_entries at v8. The backfill
// must leave it exactly as-is (log_entries is explicitly out of scope).
const _existingLogSyncId = 'LOG-FIXED-UUID-0001';

// Seconds-since-epoch instants (drift stores DateTime as unix seconds).
const _ts = 1700000000;
const _logStart = 1700000000;
const _logEnd = 1700003600;

void main() {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v8 -> v9: backfills syncId on all four tables, preserves data, '
      'leaves log_entries syncId untouched', () async {
    final schema = await verifier.schemaAt(8);
    final raw = schema.rawDatabase;

    // Seed real rows at the v8 shape. syncId is left NULL on the four in-scope
    // tables (intention_tasks has no such column at v8 at all).
    raw.execute("INSERT INTO categories "
        "(name, color_value, is_archived, is_system, created_at) "
        "VALUES ('Work', 100, 0, 0, $_ts), ('Sleep', 200, 0, 1, $_ts)");
    raw.execute("INSERT INTO routine_slots "
        "(label, day_of_week, start_hour, duration_hours, is_active, created_at) "
        "VALUES ('Morning', 1, 6, 2, 1, $_ts), ('Evening', 0, 18, 1, 1, $_ts)");
    raw.execute("INSERT INTO daily_intentions "
        "(intention, date, was_reflected, created_at) "
        "VALUES ('Focus', $_ts, 0, $_ts), ('Rest', $_ts, 0, $_ts)");
    raw.execute("INSERT INTO intention_tasks "
        "(label, is_done, is_flagged, sort_order, date) "
        "VALUES ('Task A', 0, 0, 1, $_ts), ('Task B', 0, 0, 2, $_ts)");
    // log_entries already carries a non-null syncId at v8 — must survive.
    raw.execute("INSERT INTO log_entries "
        "(description, start_time, end_time, is_real_time, is_ai_parsed, "
        "is_usage_derived, created_at, sync_id) "
        "VALUES ('Existing', $_logStart, $_logEnd, 1, 0, 0, $_ts, "
        "'$_existingLogSyncId')");

    // Run the REAL migration to v9 through the app's own onUpgrade.
    final db = AppDatabase(schema.newConnection());
    addTearDown(() async => db.close());
    await verifier.migrateAndValidate(db, 9);

    // ── Per-table assertions ────────────────────────────────────────────────
    final cats = await db.select(db.categories).get();
    final slots = await db.select(db.routineSlots).get();
    final intentions = await db.select(db.dailyIntentions).get();
    final tasks = await db.select(db.intentionTasks).get();
    final logs = await db.select(db.logEntries).get();

    // Every seeded row still exists.
    expect(cats, hasLength(2));
    expect(slots, hasLength(2));
    expect(intentions, hasLength(2));
    expect(tasks, hasLength(2));
    expect(logs, hasLength(1));

    // Key fields intact.
    expect(cats.map((c) => c.name).toSet(), {'Work', 'Sleep'});
    expect(
      {for (final c in cats) c.name: c.colorValue},
      {'Work': 100, 'Sleep': 200},
    );
    expect(slots.map((s) => s.label).toSet(), {'Morning', 'Evening'});
    expect(intentions.map((i) => i.intention).toSet(), {'Focus', 'Rest'});
    expect(tasks.map((t) => t.label).toSet(), {'Task A', 'Task B'});
    expect(logs.single.startTime.millisecondsSinceEpoch, _logStart * 1000);
    expect(logs.single.endTime.millisecondsSinceEpoch, _logEnd * 1000);

    // Every in-scope row now has a NON-NULL syncId.
    for (final c in cats) {
      expect(c.syncId, isNotNull, reason: 'category ${c.name}');
    }
    for (final s in slots) {
      expect(s.syncId, isNotNull, reason: 'slot ${s.label}');
    }
    for (final i in intentions) {
      expect(i.syncId, isNotNull, reason: 'intention ${i.intention}');
    }
    for (final t in tasks) {
      expect(t.syncId, isNotNull, reason: 'task ${t.label}');
    }

    // All syncIds across the four in-scope tables are UNIQUE (no collision).
    final inScopeSyncIds = <String>[
      ...cats.map((c) => c.syncId!),
      ...slots.map((s) => s.syncId!),
      ...intentions.map((i) => i.syncId!),
      ...tasks.map((t) => t.syncId!),
    ];
    expect(inScopeSyncIds, hasLength(8));
    expect(inScopeSyncIds.toSet(), hasLength(8),
        reason: 'every backfilled syncId must be unique');

    // log_entries syncId is UNCHANGED (not regenerated).
    expect(logs.single.syncId, _existingLogSyncId);

    // schemaVersion is 9 after migration.
    final userVersion = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(userVersion, 9);
  });

  test('v8 -> v9: empty tables stay empty and migration still succeeds',
      () async {
    final schema = await verifier.schemaAt(8);
    // Seed ONLY categories; leave the other three in-scope tables empty.
    schema.rawDatabase.execute("INSERT INTO categories "
        "(name, color_value, is_archived, is_system, created_at) "
        "VALUES ('Solo', 7, 0, 0, $_ts)");

    final db = AppDatabase(schema.newConnection());
    addTearDown(() async => db.close());

    // Must not crash on empty tables.
    await verifier.migrateAndValidate(db, 9);

    final cats = await db.select(db.categories).get();
    expect(cats, hasLength(1));
    expect(cats.single.syncId, isNotNull);

    // Empty tables stay empty.
    expect(await db.select(db.routineSlots).get(), isEmpty);
    expect(await db.select(db.dailyIntentions).get(), isEmpty);
    expect(await db.select(db.intentionTasks).get(), isEmpty);
    expect(await db.select(db.logEntries).get(), isEmpty);

    final userVersion = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(userVersion, 9);
  });
}
