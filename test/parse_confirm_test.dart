import 'dart:ffi';

import 'package:chronoplan/core/ai/groq_service.dart';
import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/log_entry/log_entry_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

void main() {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  final hourStart = DateTime(2026, 7, 14, 10, 0);
  DateTime at(int minute) => hourStart.add(Duration(minutes: minute));

  ParsedEntry entry(String desc, int startMin, int endMin) => ParsedEntry(
        description: desc,
        suggestedCategory: null,
        startTime: at(startMin),
        endTime: at(endMin),
      );

  /// Existing screen-time row, exactly as the confirm/carve paths write it
  /// (default `avoidUsageDerived`, so it always lands whole).
  Future<void> seedScreenTime(
    AppDatabase db, {
    required int startMin,
    required int endMin,
  }) async {
    final seeded = await db.logEntriesDao.insertRetroactive(
      startTime: at(startMin),
      endTime: at(endMin),
      categoryId: null,
      description: 'YouTube',
      isUsageDerived: true,
    );
    expect(seeded.ids.length, 1, reason: 'seed should land as a single row');
  }

  Future<int> rowCount(AppDatabase db, String desc) async {
    final all = await db.logEntriesDao.getForDay(hourStart);
    return all.where((e) => e.description == desc).length;
  }

  group('writeParsedEntries', () {
    test('1. all entries write cleanly → all added, full-success (no message)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final entries = [entry('A', 0, 30), entry('B', 30, 60)];

      final outcome = await writeParsedEntries(db, entries, const []);

      expect(outcome.added, entries);
      expect(outcome.blocked, 0);
      expect(outcome.failed, 0);
      expect(await rowCount(db, 'A'), 1);
      expect(await rowCount(db, 'B'), 1);
      // added == total → the sheet-close path; no outcome message.
      expect(
        confirmMessageFor(added: outcome.added.length, blocked: 0, failed: 0),
        isNull,
      );

      await db.close();
    });

    test('2. one window fully covered → blocked, others added, right message',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await seedScreenTime(db, startMin: 30, endMin: 60); // covers B
      final entries = [entry('A', 0, 30), entry('B', 30, 60)];

      final outcome = await writeParsedEntries(db, entries, const []);

      expect(outcome.added, [entries[0]]);
      expect(outcome.blocked, 1);
      expect(outcome.failed, 0);
      expect(await rowCount(db, 'A'), 1);
      expect(await rowCount(db, 'B'), 0, reason: 'B was fully covered');

      final total = outcome.added.length + outcome.blocked + outcome.failed;
      expect(total, 2);
      expect(
        confirmMessageFor(added: 1, blocked: 1, failed: 0),
        'Added 1 of 2. 1 already covered.',
      );

      await db.close();
    });

    test('3. partially-covered entry counts as ADDED (no trim message)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await seedScreenTime(db, startMin: 20, endMin: 40); // bites the middle
      final entries = [entry('A', 0, 60)];

      final outcome = await writeParsedEntries(db, entries, const []);

      expect(outcome.added, entries, reason: 'a trimmed write still counts');
      expect(outcome.blocked, 0);
      expect(outcome.failed, 0);
      // Slotted around the blocker → two rows, but one logical "added" entry.
      expect(await rowCount(db, 'A'), 2);
      // added == total → no message at all, so nothing is said about the trim.
      expect(confirmMessageFor(added: 1, blocked: 0, failed: 0), isNull);

      await db.close();
    });

    test('4. all entries blocked → added == 0, right message, nothing written',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await seedScreenTime(db, startMin: 0, endMin: 60); // covers the whole hour
      final entries = [entry('A', 0, 30), entry('B', 30, 60)];

      final outcome = await writeParsedEntries(db, entries, const []);

      expect(outcome.added, isEmpty);
      expect(outcome.blocked, 2);
      expect(outcome.failed, 0);
      expect(await rowCount(db, 'A'), 0);
      expect(await rowCount(db, 'B'), 0);
      expect(
        confirmMessageFor(added: 0, blocked: 2, failed: 0),
        'Nothing added — those times are already covered.',
      );

      await db.close();
    });

    test('5a. re-confirm attempts ONLY the remaining entries (no duplicates)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await seedScreenTime(db, startMin: 30, endMin: 60); // covers B
      final entries = [entry('A', 0, 30), entry('B', 30, 60)];

      // First confirm: A lands, B blocked.
      final first = await writeParsedEntries(db, entries, const []);
      expect(first.added, [entries[0]]);

      // The widget removes the added entries from its pending list; the retry
      // only carries what did NOT land.
      final written = first.added.toSet();
      final remaining =
          entries.where((e) => !written.contains(e)).toList();
      expect(remaining, [entries[1]]);

      // Second confirm attempts only B.
      final second = await writeParsedEntries(db, remaining, const []);
      expect(second.added, isEmpty);
      expect(second.blocked, 1);

      expect(await rowCount(db, 'A'), 1, reason: 'A must not be written twice');
      expect(await rowCount(db, 'B'), 0);

      await db.close();
    });

    test('5b. WITHOUT removing added entries, a re-confirm DUPLICATES them '
        '(proves the removal step is load-bearing)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await seedScreenTime(db, startMin: 30, endMin: 60); // covers B
      final entries = [entry('A', 0, 30), entry('B', 30, 60)];

      // Confirm once.
      await writeParsedEntries(db, entries, const []);
      // Simulate the bug: the pending list was NOT pruned, so the full list is
      // retried verbatim.
      await writeParsedEntries(db, entries, const []);

      expect(await rowCount(db, 'A'), 2,
          reason: 'skipping the prune re-writes the already-added entry');

      await db.close();
    });

    test('6. avoidUsageDerived: true — an entry slots AROUND screen time',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await seedScreenTime(db, startMin: 20, endMin: 40);
      final entries = [entry('A', 0, 60)];

      final outcome = await writeParsedEntries(db, entries, const []);
      expect(outcome.added, entries);

      final rows = (await db.logEntriesDao.getForDay(hourStart))
          .where((e) => e.description == 'A')
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      expect(rows.length, 2, reason: 'stacked-on-top would be a single row');
      expect(rows[0].startTime, hourStart);
      expect(rows[0].endTime, at(20));
      expect(rows[1].startTime, at(40));
      expect(rows[1].endTime, at(60));
      for (final e in rows) {
        expect(e.startTime.isBefore(at(40)) && e.endTime.isAfter(at(20)),
            isFalse,
            reason: 'no logged row may overlap the screen time');
      }

      await db.close();
    });
  });

  group('confirmMessageFor', () {
    test('full success → null', () {
      expect(confirmMessageFor(added: 3, blocked: 0, failed: 0), isNull);
    });
    test('some blocked only', () {
      expect(confirmMessageFor(added: 1, blocked: 1, failed: 0),
          'Added 1 of 2. 1 already covered.');
    });
    test('some failed only', () {
      expect(confirmMessageFor(added: 1, blocked: 0, failed: 1),
          'Added 1 of 2. 1 failed to save.');
    });
    test('both blocked and failed', () {
      expect(confirmMessageFor(added: 1, blocked: 1, failed: 1),
          'Added 1 of 3. 1 already covered, 1 failed.');
    });
    test('nothing added, all blocked', () {
      expect(confirmMessageFor(added: 0, blocked: 2, failed: 0),
          'Nothing added — those times are already covered.');
    });
    test('nothing added, any failed → save failed wins', () {
      expect(confirmMessageFor(added: 0, blocked: 1, failed: 1),
          'Nothing added — save failed.');
    });
  });
}
