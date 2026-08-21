import 'dart:ffi';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/usage_stats/carve_planner.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

/// Mirrors the DB writes in `CarveActions._confirm`: shrink the entry only if
/// planCarve trimmed it, then insert each screen-time block.
Future<void> applyCarve({
  required AppDatabase db,
  required LogEntry current,
  required DateTime hourStart,
  required int screenMinutes,
  required int? screenCatId,
  required String appLabel,
}) async {
  final plan = planCarve(
    entryStart: current.startTime,
    entryEnd: current.endTime,
    hourStart: hourStart,
    screenMinutes: screenMinutes,
  );

  if (plan.newEntryEnd != current.endTime) {
    await db.logEntriesDao.updateEntry(LogEntriesCompanion(
      id: Value(current.id),
      endTime: Value(plan.newEntryEnd),
    ));
  }
  for (final (blockStart, blockEnd) in plan.screenBlocks) {
    await db.logEntriesDao.insertRetroactive(
      startTime: blockStart,
      endTime: blockEnd,
      categoryId: screenCatId,
      description: appLabel,
      isUsageDerived: true,
    );
  }
}

void main() {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  final hourStart = DateTime(2026, 7, 14, 10, 0);
  final hourEnd = DateTime(2026, 7, 14, 11, 0);

  Future<(AppDatabase, int, int)> setUpDb({
    required DateTime entryStart,
    required DateTime entryEnd,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final catId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Learning', colorValue: 0xFF000000),
        );
    final screenTimeCatId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
              name: 'Screen Time', colorValue: 0xFF000000),
        );
    final entryId = await db.logEntriesDao.insertRealTime(
      startTime: entryStart,
      endTime: entryEnd,
      categoryId: catId,
      description: 'Learning',
    );
    return (db, entryId, screenTimeCatId);
  }

  test('carve 13m from a 60m entry shrinks it to 47m and adds a 13m block',
      () async {
    final (db, entryId, screenTimeCatId) =
        await setUpDb(entryStart: hourStart, entryEnd: hourEnd);

    final current = await db.logEntriesDao.getById(entryId);
    await applyCarve(
      db: db,
      current: current!,
      hourStart: hourStart,
      screenMinutes: 13,
      screenCatId: screenTimeCatId,
      appLabel: 'YouTube',
    );

    final all = await db.logEntriesDao.getForDay(hourStart);
    expect(all.length, 2, reason: 'expected the entry to split into 2 rows');
    final learning = all.firstWhere((e) => e.description == 'Learning');
    final youtube = all.firstWhere((e) => e.description == 'YouTube');
    expect(learning.startTime, hourStart, reason: 'start is never moved');
    expect(learning.endTime.difference(learning.startTime).inMinutes, 47);
    expect(youtube.endTime.difference(youtube.startTime).inMinutes, 13);
    expect(youtube.endTime, hourEnd);

    await db.close();
  });

  test('carving 70m from a 60m entry keeps the entry alive with 1 minute',
      () async {
    final (db, entryId, screenTimeCatId) =
        await setUpDb(entryStart: hourStart, entryEnd: hourEnd);

    // The provider caps at 60; exercise the over-limit value end-to-end anyway.
    final current = await db.logEntriesDao.getById(entryId);
    await applyCarve(
      db: db,
      current: current!,
      hourStart: hourStart,
      screenMinutes: 70,
      screenCatId: screenTimeCatId,
      appLabel: 'YouTube',
    );

    final all = await db.logEntriesDao.getForDay(hourStart);
    expect(all.length, 2, reason: 'the logged entry must never be erased');
    final learning = all.firstWhere((e) => e.description == 'Learning');
    final youtube = all.firstWhere((e) => e.description == 'YouTube');
    expect(learning.startTime, hourStart);
    expect(learning.endTime.difference(learning.startTime).inMinutes, 1);
    expect(youtube.endTime.difference(youtube.startTime).inMinutes, 59);
    expect(youtube.endTime, hourEnd);

    await db.close();
  });

  test('a 20m entry + 30m of screen time keeps the entry whole', () async {
    final entryEnd = hourStart.add(const Duration(minutes: 20));
    final (db, entryId, screenTimeCatId) =
        await setUpDb(entryStart: hourStart, entryEnd: entryEnd);

    final current = await db.logEntriesDao.getById(entryId);
    await applyCarve(
      db: db,
      current: current!,
      hourStart: hourStart,
      screenMinutes: 30,
      screenCatId: screenTimeCatId,
      appLabel: 'YouTube',
    );

    final all = await db.logEntriesDao.getForDay(hourStart);
    expect(all.length, 2);
    final learning = all.firstWhere((e) => e.description == 'Learning');
    final youtube = all.firstWhere((e) => e.description == 'YouTube');
    expect(learning.startTime, hourStart);
    expect(learning.endTime, entryEnd, reason: 'no trim was needed');
    expect(youtube.startTime, entryEnd);
    expect(youtube.endTime.difference(youtube.startTime).inMinutes, 30);

    await db.close();
  });

  test('a mid-hour entry gets screen time as two non-overlapping blocks',
      () async {
    final entryStart = hourStart.add(const Duration(minutes: 20));
    final entryEnd = hourStart.add(const Duration(minutes: 40));
    final (db, entryId, screenTimeCatId) =
        await setUpDb(entryStart: entryStart, entryEnd: entryEnd);

    final current = await db.logEntriesDao.getById(entryId);
    await applyCarve(
      db: db,
      current: current!,
      hourStart: hourStart,
      screenMinutes: 30,
      screenCatId: screenTimeCatId,
      appLabel: 'YouTube',
    );

    final all = await db.logEntriesDao.getForDay(hourStart);
    expect(all.length, 3, reason: 'entry + two screen-time blocks');

    final learning = all.firstWhere((e) => e.description == 'Learning');
    expect(learning.startTime, entryStart, reason: 'start is never moved');
    expect(learning.endTime, entryEnd, reason: 'no trim was needed');

    // Rows come back sorted by startTime — check the whole hour tiles cleanly.
    var total = 0;
    for (var i = 0; i < all.length; i++) {
      total += all[i].endTime.difference(all[i].startTime).inMinutes;
      if (i > 0) {
        expect(all[i].startTime.isBefore(all[i - 1].endTime), isFalse,
            reason: 'rows ${i - 1} and $i overlap');
      }
    }
    expect(total, 50);

    await db.close();
  });
}
