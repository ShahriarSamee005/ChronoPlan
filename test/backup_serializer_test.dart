import 'dart:convert';

import 'package:chronoplan/core/backup/backup_serializer.dart';
import 'package:chronoplan/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure serializer tests — no database, no sqlite. Rows are hand-built via the
/// generated Drift data-class constructors and fed straight to buildBackupMap.
void main() {
  final t0 = DateTime.utc(2026, 1, 2, 3, 4, 5);

  Category cat(int id, String name) => Category(
        id: id,
        name: name,
        colorValue: 0xFF5E60CE,
        isArchived: false,
        isSystem: false,
        createdAt: t0,
      );

  LogEntry log(int id) => LogEntry(
        id: id,
        description: 'work',
        categoryId: 1,
        startTime: t0,
        endTime: t0.add(const Duration(hours: 1)),
        isRealTime: true,
        isAiParsed: false,
        isUsageDerived: false,
        createdAt: t0,
      );

  Map<String, dynamic> build({
    List<Category> categories = const [],
    List<LogEntry> logEntries = const [],
    int schemaVersion = 8,
    DateTime? exportedAt,
    String? appVersion,
  }) =>
      buildBackupMap(
        categories: categories,
        logEntries: logEntries,
        routineSlots: const [],
        dailyIntentions: const [],
        userSettings: const [],
        dismissedSuggestions: const [],
        dismissedCarves: const [],
        intentionTasks: const [],
        schemaVersion: schemaVersion,
        exportedAt: exportedAt,
        appVersion: appVersion,
      );

  group('buildBackupMap envelope', () {
    test('carries schemaVersion and an ISO-8601 UTC timestamp', () {
      final map = build(exportedAt: t0, schemaVersion: 8);

      expect(map['schemaVersion'], 8);
      expect(map['exportedAt'], '2026-01-02T03:04:05.000Z');
    });

    test('emits appVersion only when supplied', () {
      expect(build().containsKey('appVersion'), isFalse);
      expect(build(appVersion: '1.0.0+1')['appVersion'], '1.0.0+1');
    });

    test('normalizes a local exportedAt to UTC', () {
      final local = DateTime(2026, 1, 2, 3, 4, 5); // not UTC
      final map = build(exportedAt: local);
      expect((map['exportedAt'] as String).endsWith('Z'), isTrue);
    });

    test('has an entry for every one of the 8 tables', () {
      final tables = build()['tables'] as Map<String, dynamic>;
      expect(
        tables.keys.toSet(),
        {
          kTableCategories,
          kTableLogEntries,
          kTableRoutineSlots,
          kTableDailyIntentions,
          kTableUserSettings,
          kTableDismissedSuggestions,
          kTableDismissedCarves,
          kTableIntentionTasks,
        },
      );
      expect(tables.length, 8);
    });
  });

  group('buildBackupMap rows', () {
    test('empty tables serialize to empty lists', () {
      final tables = build()['tables'] as Map<String, dynamic>;
      for (final v in tables.values) {
        expect(v, isA<List>());
        expect(v, isEmpty);
      }
    });

    test('preserves row count and content per table', () {
      final map = build(
        categories: [cat(1, 'Work'), cat(2, 'Sleep')],
        logEntries: [log(10)],
      );
      final tables = map['tables'] as Map<String, dynamic>;

      final cats = tables[kTableCategories] as List;
      expect(cats.length, 2);
      expect((cats.first as Map)['name'], 'Work');
      expect((cats.first as Map)['colorValue'], 0xFF5E60CE);

      final logs = tables[kTableLogEntries] as List;
      expect(logs.length, 1);
      expect((logs.first as Map)['id'], 10);
      expect((logs.first as Map)['isRealTime'], anyOf(true, 1));
    });
  });

  // ── LOAD-BEARING for Phase 6 restore ──────────────────────────────────────
  // If DateTime columns don't survive JSON as a reversible instant, restore
  // corrupts every timestamp. This test pins that contract: serialized value is
  // an int (ms since epoch) and reverses to the identical instant, even through
  // a real jsonEncode/decode. Break the serializer's DateTime handling (e.g.
  // emit a String) and this test fails.
  test('DateTime columns round-trip to the identical instant through JSON', () {
    final dt = DateTime.utc(2026, 3, 4, 5, 6, 7, 890);
    final entry = LogEntry(
      id: 42,
      description: 'deep work',
      categoryId: 1,
      startTime: dt,
      endTime: dt.add(const Duration(minutes: 90)),
      isRealTime: true,
      isAiParsed: false,
      isUsageDerived: false,
      createdAt: dt,
    );

    final map = build(logEntries: [entry], exportedAt: t0);
    final decoded = jsonDecode(jsonEncode(map)) as Map<String, dynamic>;
    final row =
        ((decoded['tables'] as Map)[kTableLogEntries] as List).single as Map;

    // Format contract: DateTime serializes as an int (ms since epoch).
    expect(row['startTime'], isA<int>());
    expect(row['startTime'], dt.millisecondsSinceEpoch);

    // Reversibility: the int reconstructs the exact same instant.
    final restored =
        DateTime.fromMillisecondsSinceEpoch(row['startTime'] as int, isUtc: true);
    expect(restored.isAtSameMomentAs(dt), isTrue);
    expect(restored, dt);
  });

  test('the whole map round-trips through jsonEncode/decode', () {
    final map = build(
      categories: [cat(1, 'Work')],
      logEntries: [log(10)],
      exportedAt: t0,
    );

    final encoded = jsonEncode(map);
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;

    expect(decoded['schemaVersion'], 8);
    expect(decoded['exportedAt'], '2026-01-02T03:04:05.000Z');
    expect(
      ((decoded['tables'] as Map)[kTableCategories] as List).length,
      1,
    );
  });
}
