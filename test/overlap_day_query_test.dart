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

  // Fixed dates so the test never depends on the wall clock.
  final today = DateTime(2026, 8, 24);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));

  DateTime on(DateTime day, int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  Future<void> seed(
    AppDatabase db, {
    required DateTime start,
    required DateTime end,
    required String description,
  }) async {
    final result = await db.logEntriesDao.insertRetroactive(
      startTime: start,
      endTime: end,
      categoryId: null,
      description: description,
    );
    expect(result.ids.length, 1, reason: 'seed should land as a single row');
  }

  test('a cross-midnight entry from yesterday is included in today', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seed(db,
        start: on(yesterday, 23), end: on(today, 6, 45), description: 'Sleep');

    final entries =
        await db.logEntriesDao.watchEntriesOverlappingDay(today).first;

    expect(entries.map((e) => e.description), contains('Sleep'));
    await db.close();
  });

  test('an entry entirely on the prior day is excluded', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seed(db,
        start: on(yesterday, 10),
        end: on(yesterday, 11),
        description: 'Yesterday only');

    final entries =
        await db.logEntriesDao.watchEntriesOverlappingDay(today).first;

    expect(entries, isEmpty);
    await db.close();
  });

  test('a normal same-day entry is included', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seed(db,
        start: on(today, 9), end: on(today, 10), description: 'Deep work');

    final entries =
        await db.logEntriesDao.watchEntriesOverlappingDay(today).first;

    expect(entries.map((e) => e.description), contains('Deep work'));
    await db.close();
  });

  test('an entry crossing forward into tomorrow is included', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seed(db,
        start: on(today, 23, 30),
        end: on(tomorrow, 1),
        description: 'Late session');

    final entries =
        await db.logEntriesDao.watchEntriesOverlappingDay(today).first;

    expect(entries.map((e) => e.description), contains('Late session'));
    await db.close();
  });

  test('an entry ending exactly at midnight is excluded', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seed(db,
        start: on(yesterday, 22),
        end: on(today, 0),
        description: 'Ends at midnight');

    final entries =
        await db.logEntriesDao.watchEntriesOverlappingDay(today).first;

    expect(entries, isEmpty,
        reason: 'endTime must be strictly greater than dayStart');
    await db.close();
  });

  test('watchForDay is unchanged and still excludes the crosser', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seed(db,
        start: on(yesterday, 23), end: on(today, 6, 45), description: 'Sleep');

    final byStart = await db.logEntriesDao.watchForDay(today).first;

    expect(byStart, isEmpty,
        reason: 'watchForDay filters by startTime only');
    await db.close();
  });
}
