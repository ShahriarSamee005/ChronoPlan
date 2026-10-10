// ---------------------------------------------------------------------------
// Drift migration-test harness (Backup Phase 2a).
//
// This is the reusable machinery that Phase 2b (the v8 -> v9 migration for
// `sync_id`) will build on. It opens the database AT A SPECIFIC, FROZEN schema
// version using Drift's generated `SchemaVerifier` and verifies that the
// runtime schema matches what the generated code expects.
//
// Regenerating the schema snapshots (do this in 2b, AFTER bumping schemaVersion
// and adding the migration step, so the ladder has a v9 to freeze):
//
//   dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/
//   mkdir -p test/drift/generated        # `schema generate` does NOT mkdir parents
//   dart run drift_dev schema generate drift_schemas/ test/drift/generated/
//
// The first command writes `drift_schemas/drift_schema_v<N>.json`; the second
// (re)writes `test/drift/generated/schema.dart` + `schema_v<N>.dart`. Both the
// snapshots and the generated helpers are build artifacts — not committed.
//
// The sqlite3 DLL path below is the SAME machine-specific path every other
// DB-backed test in this repo hardcodes (see e.g. backup_read_layer_test.dart).
// `open.overrideFor` is global, so it also covers the in-memory connections
// `SchemaVerifier` opens internally.
//
// How 2b will use this: after freezing v9, add a test here that seeds a v8 DB
// via `verifier.schemaAt(8)`, connects `AppDatabase` to it, calls
// `verifier.migrateAndValidate(db, 9)`, and asserts the new `sync_id` column
// exists and pre-existing rows survived the migration.
// ---------------------------------------------------------------------------

import 'dart:ffi';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

import 'generated/schema.dart';

void main() {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('harness scaffold: open AppDatabase at v8 and verify schema integrity',
      () async {
    // startAt(8) builds an empty DB with the frozen v8 schema. Connecting
    // AppDatabase and running migrateAndValidate to its own current version (8)
    // exercises the full harness path and confirms the runtime schema matches
    // the generated v8 snapshot. A SchemaMismatch would throw here.
    final connection = await verifier.startAt(8);
    final db = AppDatabase(connection);

    await verifier.migrateAndValidate(db, 8);

    await db.close();
  });

  // NOTE: no older-version (e.g. v6 -> v8) data-integrity test is included.
  // The generated helper only knows v8 (`GeneratedHelper.versions == [8]`)
  // because only the current schema was dumped. Testing an existing migration
  // step would require dumping historical schema versions from git history,
  // which is out of scope for Phase 2a (and hand-written dumps are forbidden).
  // 2b adds the v9 dump and can then exercise the v8 -> v9 step directly.
}
