// ---------------------------------------------------------------------------
// Backup Phase 2b — going-forward insert coverage.
//
// Separate from the migration proof: these run against a FRESH v9 database and
// prove that the real DAOs stamp a non-null, unique syncId on every row they
// create (categories, routine_slots, daily_intentions, intention_tasks),
// including insertDefaults and copyDaySlots. log_entries is out of scope here.
//
// Uses the same sqlite3 DLL load the other DB-backed tests use on this box.
// ---------------------------------------------------------------------------

import 'dart:ffi';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

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

  test('DAO inserts stamp a non-null unique syncId on each of the four tables',
      () async {
    final catId = await db.categoriesDao.insertCategory(
      CategoriesCompanion.insert(name: 'Reading', colorValue: 123),
    );
    final slotId = await db.routineSlotsDao.insertSlot(
      RoutineSlotsCompanion.insert(dayOfWeek: 1, startHour: 8),
    );
    await db.intentionsDao.upsertForDate(DateTime(2026, 1, 2), 'Ship it');
    await db.intentionTasksDao.addTask(DateTime(2026, 1, 2), 'Write tests');

    final cat =
        await (db.select(db.categories)..where((c) => c.id.equals(catId)))
            .getSingle();
    final slot =
        await (db.select(db.routineSlots)..where((s) => s.id.equals(slotId)))
            .getSingle();
    final intention = await db.select(db.dailyIntentions).getSingle();
    final task = await db.select(db.intentionTasks).getSingle();

    expect(cat.syncId, isNotNull);
    expect(slot.syncId, isNotNull);
    expect(intention.syncId, isNotNull);
    expect(task.syncId, isNotNull);

    final ids = {cat.syncId!, slot.syncId!, intention.syncId!, task.syncId!};
    expect(ids, hasLength(4), reason: 'syncIds must be distinct across tables');
  });

  test('a caller-supplied non-null syncId is NOT overwritten', () async {
    const supplied = 'CALLER-SUPPLIED-0001';
    final id = await db.categoriesDao.insertCategory(
      CategoriesCompanion.insert(
        name: 'Imported',
        colorValue: 1,
        syncId: const Value(supplied),
      ),
    );
    final cat =
        await (db.select(db.categories)..where((c) => c.id.equals(id)))
            .getSingle();
    expect(cat.syncId, supplied);
  });

  test('insertDefaults: all 11 seeded categories get non-null unique syncIds',
      () async {
    // onCreate already runs insertDefaults() when the fresh DB opens, so the 11
    // defaults are present without a second call (calling it again would double
    // the set). Reading them back exercises the insertDefaults stamping path.
    final cats = await db.select(db.categories).get();
    expect(cats, hasLength(11));
    for (final c in cats) {
      expect(c.syncId, isNotNull, reason: c.name);
    }
    expect(cats.map((c) => c.syncId!).toSet(), hasLength(11),
        reason: 'all seeded syncIds unique');
  });

  test('copyDaySlots: copying N slots yields N distinct new syncIds', () async {
    // Three day-specific slots on Monday (dayOfWeek == 1).
    for (var h = 6; h < 9; h++) {
      await db.routineSlotsDao.insertSlot(
        RoutineSlotsCompanion.insert(dayOfWeek: 1, startHour: h),
      );
    }

    await db.routineSlotsDao.copyDaySlots(1, [2, 3]); // -> Tue, Wed

    final copies = await (db.select(db.routineSlots)
          ..where((s) => s.dayOfWeek.isIn([2, 3])))
        .get();
    expect(copies, hasLength(6)); // 3 slots x 2 days
    for (final s in copies) {
      expect(s.syncId, isNotNull);
    }
    final copySyncIds = copies.map((s) => s.syncId!).toList();
    expect(copySyncIds.toSet(), hasLength(6),
        reason: 'each copied slot gets its OWN fresh uuid');
  });

  test('rollForward only moves the date and leaves syncId untouched', () async {
    // addTask stamps a syncId; rollForward is UPDATE-only and must not touch it.
    await db.intentionTasksDao.addTask(DateTime(2026, 1, 1), 'Carry me');
    final before = await db.select(db.intentionTasks).getSingle();
    expect(before.syncId, isNotNull);

    await db.intentionTasksDao.rollForward(DateTime(2026, 1, 5));

    final after = await db.select(db.intentionTasks).getSingle();
    expect(after.syncId, before.syncId, reason: 'syncId unchanged by rollForward');
    expect(after.date, DateTime(2026, 1, 5), reason: 'date rolled forward');
  });
}
