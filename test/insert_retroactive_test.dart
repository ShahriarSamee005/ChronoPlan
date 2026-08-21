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

  final hourStart = DateTime(2026, 7, 14, 10, 0);
  final hourEnd = DateTime(2026, 7, 14, 11, 0);
  DateTime at(int minute) => hourStart.add(Duration(minutes: minute));

  /// Writes an existing screen-time row, exactly as the confirm/carve paths do
  /// (they leave `avoidUsageDerived` at its default, so this always lands whole).
  Future<void> seedScreenTime(
    AppDatabase db, {
    required DateTime start,
    required DateTime end,
  }) async {
    final seeded = await db.logEntriesDao.insertRetroactive(
      startTime: start,
      endTime: end,
      categoryId: null,
      description: 'YouTube',
      isUsageDerived: true,
    );
    expect(seeded.ids.length, 1, reason: 'seed should land as a single row');
  }

  Future<({List<int> ids, int requestedMinutes, int writtenMinutes})> logByHand(
    AppDatabase db, {
    required bool avoidUsageDerived,
    DateTime? start,
    DateTime? end,
  }) =>
      db.logEntriesDao.insertRetroactive(
        startTime: start ?? hourStart,
        endTime: end ?? hourEnd,
        categoryId: null,
        description: 'Deep work',
        avoidUsageDerived: avoidUsageDerived,
      );

  test('screen time mid-range splits the manual log into two rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedScreenTime(db, start: at(20), end: at(40));

    final result = await logByHand(db, avoidUsageDerived: true);

    expect(result.ids.length, 2);
    expect(result.requestedMinutes, 60);
    expect(result.writtenMinutes, 60 - 20,
        reason: 'the 20m screen-time block is skipped');

    final logs = (await db.logEntriesDao.getForDay(hourStart))
        .where((e) => e.description == 'Deep work')
        .toList();
    expect(logs.length, 2);
    expect(logs[0].startTime, hourStart);
    expect(logs[0].endTime, at(20));
    expect(logs[1].startTime, at(40));
    expect(logs[1].endTime, hourEnd);

    // No manual row may overlap the screen-time block.
    for (final e in logs) {
      expect(e.startTime.isBefore(at(40)) && e.endTime.isAfter(at(20)), isFalse,
          reason: 'row ${e.startTime}–${e.endTime} overlaps the screen time');
    }

    await db.close();
  });

  test('a fully covered range writes nothing and reports zero minutes',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedScreenTime(db, start: hourStart, end: hourEnd);

    final result = await logByHand(db, avoidUsageDerived: true);

    expect(result.ids, isEmpty);
    expect(result.writtenMinutes, 0);
    expect(result.requestedMinutes, 60);

    final all = await db.logEntriesDao.getForDay(hourStart);
    expect(all.length, 1, reason: 'only the screen-time row exists');
    expect(all.single.description, 'YouTube');

    await db.close();
  });

  test('no screen time in range → one row covering the whole request',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    // Screen time in a DIFFERENT hour must not interfere.
    await seedScreenTime(
      db,
      start: hourStart.add(const Duration(hours: 2)),
      end: hourStart.add(const Duration(hours: 3)),
    );

    final result = await logByHand(db, avoidUsageDerived: true);

    expect(result.ids.length, 1);
    expect(result.writtenMinutes, result.requestedMinutes);
    expect(result.writtenMinutes, 60);

    final logs = (await db.logEntriesDao.getForDay(hourStart))
        .where((e) => e.description == 'Deep work');
    expect(logs.single.startTime, hourStart);
    expect(logs.single.endTime, hourEnd);

    await db.close();
  });

  test('with the flag off, screen time does not block (today\'s behavior)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedScreenTime(db, start: at(20), end: at(40));

    final result = await logByHand(db, avoidUsageDerived: false);

    expect(result.ids.length, 1, reason: 'one row spanning the whole range');
    expect(result.writtenMinutes, 60);
    expect(result.writtenMinutes, result.requestedMinutes);

    final logs = (await db.logEntriesDao.getForDay(hourStart))
        .where((e) => e.description == 'Deep work');
    expect(logs.single.startTime, hourStart);
    expect(logs.single.endTime, hourEnd);

    await db.close();
  });

  test('a real-time entry blocks regardless of the flag', () async {
    for (final avoid in [false, true]) {
      final db = AppDatabase(NativeDatabase.memory());
      await db.logEntriesDao.insertRealTime(
        startTime: at(20),
        endTime: at(40),
        categoryId: null,
        description: 'Meeting',
      );

      final result = await logByHand(db, avoidUsageDerived: avoid);

      expect(result.ids.length, 2,
          reason: 'real-time entries are sacred (avoid=$avoid)');
      expect(result.writtenMinutes, 40, reason: 'avoid=$avoid');

      final logs = (await db.logEntriesDao.getForDay(hourStart))
          .where((e) => e.description == 'Deep work')
          .toList();
      expect(logs[0].endTime, at(20), reason: 'avoid=$avoid');
      expect(logs[1].startTime, at(40), reason: 'avoid=$avoid');

      await db.close();
    }
  });

  test('screen time at both ends leaves only the middle', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedScreenTime(db, start: hourStart, end: at(15));
    await seedScreenTime(db, start: at(45), end: hourEnd);

    final result = await logByHand(db, avoidUsageDerived: true);

    expect(result.ids.length, 1);
    expect(result.writtenMinutes, 30);
    expect(result.requestedMinutes, 60);

    final logs = (await db.logEntriesDao.getForDay(hourStart))
        .where((e) => e.description == 'Deep work');
    expect(logs.single.startTime, at(15));
    expect(logs.single.endTime, at(45));

    await db.close();
  });
}
