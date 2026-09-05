import 'package:chronoplan/features/dashboard/current_slot_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a [PlanSlotInput] with sensible defaults so each test only states
/// the fields it cares about.
PlanSlotInput slot({
  int id = 1,
  int startHour = 9,
  int durationHours = 1,
  int dayOfWeek = 0,
  bool isActive = true,
  String label = '',
  int? categoryId,
}) =>
    (
      id: id,
      startHour: startHour,
      durationHours: durationHours,
      dayOfWeek: dayOfWeek,
      isActive: isActive,
      label: label,
      categoryId: categoryId,
    );

void main() {
  // Fixed "now": 2026-08-27 is a Thursday (weekday == 4), 09:30.
  final now = DateTime(2026, 8, 27, 9, 30);

  group('slotForHour', () {
    test('1: single slot covering the hour → returned', () {
      final s = slot(id: 7, startHour: 9, durationHours: 1, dayOfWeek: 4);
      final result = slotForHour([s], now: now);
      expect(result, isNotNull);
      expect(result!.id, 7);
    });

    test('2: slot for a different weekday → null', () {
      // now is Thursday (4); this slot is Friday-only (5).
      final s = slot(startHour: 9, durationHours: 1, dayOfWeek: 5);
      expect(slotForHour([s], now: now), isNull);
    });

    test('3: dayOfWeek == 0 (every day) → returned regardless of weekday', () {
      final s = slot(id: 3, startHour: 9, durationHours: 1, dayOfWeek: 0);
      final result = slotForHour([s], now: now);
      expect(result, isNotNull);
      expect(result!.id, 3);
    });

    test('4: isActive == false → null even if it covers the hour', () {
      final s = slot(
          startHour: 9, durationHours: 1, dayOfWeek: 4, isActive: false);
      expect(slotForHour([s], now: now), isNull);
    });

    test('5: multi-hour slot, now in its middle hour → returned', () {
      // 8:00–11:00 covers hours 8,9,10. now is hour 9 (the middle).
      final s = slot(id: 5, startHour: 8, durationHours: 3, dayOfWeek: 4);
      final result = slotForHour([s], now: now);
      expect(result, isNotNull);
      expect(result!.id, 5);
    });

    test('6: multi-hour slot, now exactly at its end hour → null (exclusive)',
        () {
      // 7:00–9:00 covers hours 7,8 only. now is hour 9 → end is exclusive.
      final s = slot(startHour: 7, durationHours: 2, dayOfWeek: 4);
      expect(slotForHour([s], now: now), isNull);
    });

    test('7: two overlapping slots, different startHour → earlier wins', () {
      final early = slot(id: 1, startHour: 8, durationHours: 3, dayOfWeek: 4);
      final late = slot(id: 2, startHour: 9, durationHours: 1, dayOfWeek: 4);
      // Both cover hour 9. Earlier startHour (8) wins.
      final result = slotForHour([late, early], now: now);
      expect(result, isNotNull);
      expect(result!.id, 1);
    });

    test('8: same startHour → lowest id wins, order-independent', () {
      final a = slot(id: 2, startHour: 9, durationHours: 1, dayOfWeek: 4);
      final b = slot(id: 5, startHour: 9, durationHours: 1, dayOfWeek: 4);

      // Passed in each order — the winner must be the same (determinism guard).
      final r1 = slotForHour([a, b], now: now);
      final r2 = slotForHour([b, a], now: now);
      expect(r1!.id, 2);
      expect(r2!.id, 2);
    });

    test('9: no slots at all → null', () {
      expect(slotForHour([], now: now), isNull);
    });

    test('10: slot clamped at hour 23 does not wrap to hour 0', () {
      // 23:00 + 3h would be 23,24,25 → clamped to hour 23 only.
      final s = slot(startHour: 23, durationHours: 3, dayOfWeek: 4);

      // At hour 0 the clamped slot must NOT cover → null (no wrap).
      final atMidnight = DateTime(2026, 8, 27, 0, 30);
      expect(slotForHour([s], now: atMidnight), isNull);

      // Sanity: it does still cover hour 23 on its own day.
      final at23 = DateTime(2026, 8, 27, 23, 30);
      expect(slotForHour([s], now: at23), isNotNull);
    });
  });

  group('resolveSlotName', () {
    test('11: non-empty label wins', () {
      expect(resolveSlotName('Study', 'Learning'), 'Study');
    });

    test('11: empty label falls back to category name', () {
      expect(resolveSlotName('', 'Learning'), 'Learning');
    });

    test('11: neither present → "Unlabelled"', () {
      expect(resolveSlotName('', null), 'Unlabelled');
    });
  });
}
