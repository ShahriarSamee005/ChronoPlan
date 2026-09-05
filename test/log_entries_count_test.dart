import 'dart:ffi';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

void main() {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  Future<int> insertOne(AppDatabase db, DateTime start) =>
      db.logEntriesDao.insertRealTime(
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        categoryId: null,
        description: 'Deep work',
      );

  test('countAll returns 0 on an empty log', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(await db.logEntriesDao.countAll(), 0);
    await db.close();
  });

  test('countAll returns the total number of entries across days', () async {
    final db = AppDatabase(NativeDatabase.memory());
    // Three entries, deliberately spread over two calendar days to prove the
    // count is unfiltered by day.
    await insertOne(db, DateTime(2026, 9, 4, 9, 0));
    await insertOne(db, DateTime(2026, 9, 5, 9, 0));
    await insertOne(db, DateTime(2026, 9, 5, 14, 0));

    expect(await db.logEntriesDao.countAll(), 3);
    await db.close();
  });
}
