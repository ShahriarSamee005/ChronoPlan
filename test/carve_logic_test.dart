import 'dart:ffi';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

void main() {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  test('carve 13m from a 60m entry shrinks to 47m + 13m (reproduces _confirm logic)', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final catId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Learning', colorValue: 0xFF000000),
        );
    final screenTimeCatId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Screen Time', colorValue: 0xFF000000),
        );

    final hourStart = DateTime(2026, 7, 14, 10, 0);
    final hourEnd = DateTime(2026, 7, 14, 11, 0);

    final entryId = await db.logEntriesDao.insertRealTime(
      startTime: hourStart,
      endTime: hourEnd,
      categoryId: catId,
      description: 'Learning',
    );

    const proposalDurationMinutes = 13;

    final current = await db.logEntriesDao.getById(entryId);
    final entryDuration = current!.endTime.difference(current.startTime).inMinutes;
    final carveMinutes = proposalDurationMinutes.clamp(0, entryDuration);

    final carveStart = current.endTime.subtract(Duration(minutes: carveMinutes));
    final carveEnd = current.endTime;

    if (carveMinutes >= entryDuration) {
      await db.logEntriesDao.updateEntry(LogEntriesCompanion(
        id: Value(current.id),
        categoryId: Value(screenTimeCatId),
        description: const Value('YouTube'),
        startTime: Value(carveStart),
        endTime: Value(carveEnd),
      ));
    } else {
      await db.logEntriesDao.updateEntry(LogEntriesCompanion(
        id: Value(current.id),
        endTime: Value(carveStart),
      ));
      await db.logEntriesDao.insertRetroactive(
        startTime: carveStart,
        endTime: carveEnd,
        categoryId: screenTimeCatId,
        description: 'YouTube',
      );
    }

    final all = await db.logEntriesDao.getForDay(hourStart);
    for (final e in all) {
      final mins = e.endTime.difference(e.startTime).inMinutes;
      // ignore: avoid_print
      print('${e.description}: ${e.startTime} -> ${e.endTime} (${mins}m) cat=${e.categoryId}');
    }

    expect(all.length, 2, reason: 'expected the entry to split into 2 rows');
    final learning = all.firstWhere((e) => e.description == 'Learning');
    final youtube = all.firstWhere((e) => e.description == 'YouTube');
    expect(learning.endTime.difference(learning.startTime).inMinutes, 47);
    expect(youtube.endTime.difference(youtube.startTime).inMinutes, 13);

    await db.close();
  });

  test('carving 70m (M>D) from a 60m entry caps at 60m and fully consumes it', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final catId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Learning', colorValue: 0xFF000000),
        );
    final screenTimeCatId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(name: 'Screen Time', colorValue: 0xFF000000),
        );

    final hourStart = DateTime(2026, 7, 14, 10, 0);
    final hourEnd = DateTime(2026, 7, 14, 11, 0);

    final entryId = await db.logEntriesDao.insertRealTime(
      startTime: hourStart,
      endTime: hourEnd,
      categoryId: catId,
      description: 'Learning',
    );

    // Provider-side cap would already clamp this to 60, but exercise the
    // confirm-time re-clamp directly with an over-limit value too.
    const proposalDurationMinutes = 70;

    final current = await db.logEntriesDao.getById(entryId);
    final entryDuration = current!.endTime.difference(current.startTime).inMinutes;
    final carveMinutes = proposalDurationMinutes.clamp(0, entryDuration);

    final carveStart = current.endTime.subtract(Duration(minutes: carveMinutes));
    final carveEnd = current.endTime;

    if (carveMinutes >= entryDuration) {
      await db.logEntriesDao.updateEntry(LogEntriesCompanion(
        id: Value(current.id),
        categoryId: Value(screenTimeCatId),
        description: const Value('YouTube'),
        startTime: Value(carveStart),
        endTime: Value(carveEnd),
      ));
    } else {
      await db.logEntriesDao.updateEntry(LogEntriesCompanion(
        id: Value(current.id),
        endTime: Value(carveStart),
      ));
      await db.logEntriesDao.insertRetroactive(
        startTime: carveStart,
        endTime: carveEnd,
        categoryId: screenTimeCatId,
        description: 'YouTube',
      );
    }

    final all = await db.logEntriesDao.getForDay(hourStart);
    expect(all.length, 1, reason: 'entry should be fully consumed, not split');
    expect(all.first.description, 'YouTube');
    expect(all.first.startTime, hourStart);
    expect(all.first.endTime, hourEnd);

    await db.close();
  });
}
