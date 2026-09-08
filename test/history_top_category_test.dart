import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/history/history_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

/// Build a category row. `isSystem` defaults false; pass true for Sleep /
/// Screen Time.
Category _cat(int id, String name, {bool isSystem = false}) => Category(
      id: id,
      name: name,
      colorValue: 0xFF000000,
      isArchived: false,
      isSystem: isSystem,
      createdAt: DateTime(2026, 1, 1),
    );

/// Build a log entry lasting [minutes], tagged with [categoryId] (null =
/// uncategorized: logged but never tagged with a category — not unlogged time).
LogEntry _entry(int id, int? categoryId, int minutes) {
  final start = DateTime(2026, 1, 1, 9);
  return LogEntry(
    id: id,
    description: '',
    categoryId: categoryId,
    startTime: start,
    endTime: start.add(Duration(minutes: minutes)),
    isRealTime: false,
    isAiParsed: false,
    isUsageDerived: false,
    createdAt: start,
  );
}

// Canonical category ids used across the cases.
const _work = 1;
const _sleep = 2;
const _screenTime = 3;

final _cats = [
  _cat(_work, 'Work'),
  _cat(_sleep, 'Sleep', isSystem: true),
  _cat(_screenTime, 'Screen Time', isSystem: true),
];

void main() {
  group('topCategoryFor', () {
    test('1. Sleep leads, Work second → Work', () {
      final entries = [
        _entry(1, _sleep, 480),
        _entry(2, _work, 300),
      ];
      expect(topCategoryFor(entries, _cats)?.name, 'Work');
    });

    test('2. Sleep is the only category logged → null (renders None)', () {
      final entries = [_entry(1, _sleep, 480)];
      expect(topCategoryFor(entries, _cats), isNull);
    });

    test('3. Uncategorized leads, Work second → Work', () {
      final entries = [
        _entry(1, null, 480),
        _entry(2, _work, 300),
      ];
      expect(topCategoryFor(entries, _cats)?.name, 'Work');
    });

    test('4. Sleep and uncategorized both beat Work (third) → Work', () {
      final entries = [
        _entry(1, _sleep, 480),
        _entry(2, null, 400),
        _entry(3, _work, 120),
      ];
      expect(topCategoryFor(entries, _cats)?.name, 'Work');
    });

    test('5. Only uncategorized time is logged → null', () {
      final entries = [_entry(1, null, 300)];
      expect(topCategoryFor(entries, _cats), isNull);
    });

    test('6. Screen Time leads → Screen Time (isSystem alone is NOT the filter)',
        () {
      final entries = [
        _entry(1, _screenTime, 480),
        _entry(2, _work, 300),
      ];
      expect(topCategoryFor(entries, _cats)?.name, 'Screen Time');
    });

    test('7. No entries at all → null', () {
      expect(topCategoryFor(const [], _cats), isNull);
    });

    test('8. Normal week where Work leads → Work (no behaviour change)', () {
      final entries = [
        _entry(1, _work, 600),
        _entry(2, _sleep, 480),
        _entry(3, _screenTime, 120),
      ];
      expect(topCategoryFor(entries, _cats)?.name, 'Work');
    });
  });
}
