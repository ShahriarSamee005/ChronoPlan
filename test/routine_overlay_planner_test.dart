import 'package:chronoplan/features/day_view/routine_overlay_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('planRoutineEdges', () {
    // Fixed test date: 2026-08-27 (Thursday, weekday=4)
    final testDay = DateTime(2026, 8, 27);
    final testNow = DateTime(2026, 8, 27, 10, 30); // 10:30 AM same day

    test('empty slots returns all nulls', () {
      final result = planRoutineEdges([], [], day: testDay, now: testNow);
      expect(result.length, 24);
      expect(result.every((h) => h == null), true);
    });

    test('single 1-hour slot fills its hour only', () {
      final slot = (startHour: 9, durationHours: 1, categoryId: 1);
      final result = planRoutineEdges([slot], [], day: testDay, now: testNow);

      expect(result.length, 24);
      expect(result[8], null);
      expect(result[9], isNotNull);
      expect(result[10], null);
    });

    test('3-hour slot fills all 3 hours with same verdict', () {
      final slot = (startHour: 8, durationHours: 3, categoryId: 1);
      final log = (
        start: DateTime(2026, 8, 27, 8, 0),
        end: DateTime(2026, 8, 27, 11, 0),
        categoryId: 1,
      );
      final result = planRoutineEdges([slot], [log], day: testDay, now: testNow);

      // Slot covers 8:00–11:00 (hours 8, 9, 10).
      expect(result[7], null);
      expect(result[8], isNotNull);
      expect(result[9], isNotNull);
      expect(result[10], isNotNull);
      expect(result[11], null);

      // All three hours should have the same verdict.
      final v8 = result[8]!.verdict;
      expect(result[9]!.verdict, v8);
      expect(result[10]!.verdict, v8);
    });

    test('past slot with coverage ≥0.75 + category match → green', () {
      final slot = (startHour: 9, durationHours: 1, categoryId: 1);
      // Slot: 9:00–10:00 (60 min). Log covers full hour with matching category.
      final log = (
        start: DateTime(2026, 8, 27, 9, 0),
        end: DateTime(2026, 8, 27, 10, 0),
        categoryId: 1,
      );
      final now = DateTime(2026, 8, 27, 11, 0); // Slot is past.
      final result =
          planRoutineEdges([slot], [log], day: testDay, now: now);

      expect(result[9], isNotNull);
      expect(result[9]!.isPast, true);
      expect(result[9]!.verdict, RoutineVerdict.green);
      expect(result[9]!.categoryId, 1);
    });

    test('past slot with coverage ≥0.75 but wrong category → amber', () {
      final slot = (startHour: 9, durationHours: 1, categoryId: 1);
      // Slot expects category 1. Log covers full hour but category 2.
      final log = (
        start: DateTime(2026, 8, 27, 9, 0),
        end: DateTime(2026, 8, 27, 10, 0),
        categoryId: 2,
      );
      final now = DateTime(2026, 8, 27, 11, 0);
      final result =
          planRoutineEdges([slot], [log], day: testDay, now: now);

      // Coverage is 1.0 (full hour), but category doesn't match → amber.
      expect(result[9]!.isPast, true);
      expect(result[9]!.verdict, RoutineVerdict.amber);
      expect(result[9]!.categoryId, 1);
    });

    test('past slot with coverage 0.10–0.75 → amber', () {
      final slot = (startHour: 9, durationHours: 1, categoryId: 1);
      // Slot: 9:00–10:00 (60 min). Log covers 15 min (0.25).
      final log = (
        start: DateTime(2026, 8, 27, 9, 0),
        end: DateTime(2026, 8, 27, 9, 15),
        categoryId: 1,
      );
      final now = DateTime(2026, 8, 27, 11, 0);
      final result =
          planRoutineEdges([slot], [log], day: testDay, now: now);

      expect(result[9]!.isPast, true);
      expect(result[9]!.verdict, RoutineVerdict.amber);
      expect(result[9]!.categoryId, 1);
    });

    test('past slot with coverage < 0.10 → red', () {
      final slot = (startHour: 9, durationHours: 1, categoryId: 1);
      // Slot: 9:00–10:00 (60 min). Log covers 3 min (0.05).
      final log = (
        start: DateTime(2026, 8, 27, 9, 0),
        end: DateTime(2026, 8, 27, 9, 3),
        categoryId: 1,
      );
      final now = DateTime(2026, 8, 27, 11, 0);
      final result =
          planRoutineEdges([slot], [log], day: testDay, now: now);

      expect(result[9]!.isPast, true);
      expect(result[9]!.verdict, RoutineVerdict.red);
    });

    test('slot not yet past (today, after current time) → neutral', () {
      final slot = (startHour: 14, durationHours: 1, categoryId: 1);
      // Slot: 14:00–15:00. Current time: 10:30 → slot is in future.
      final log = (
        start: DateTime(2026, 8, 27, 14, 0),
        end: DateTime(2026, 8, 27, 15, 0),
        categoryId: 1,
      );
      final result =
          planRoutineEdges([slot], [log], day: testDay, now: testNow);

      expect(result[14]!.isPast, false);
      expect(result[14]!.verdict, RoutineVerdict.neutral);
    });

    test('future day → neutral regardless of coverage', () {
      final futureDay = DateTime(2026, 8, 28);
      final slot = (startHour: 9, durationHours: 1, categoryId: 1);
      final log = (
        start: DateTime(2026, 8, 28, 9, 0),
        end: DateTime(2026, 8, 28, 10, 0),
        categoryId: 1,
      );
      final result = planRoutineEdges([slot], [log], day: futureDay, now: testNow);

      expect(result[9]!.isPast, false);
      expect(result[9]!.verdict, RoutineVerdict.neutral);
    });

    test('earlier day → treated as past', () {
      final earlierDay = DateTime(2026, 8, 26);
      final slot = (startHour: 9, durationHours: 1, categoryId: 1);
      // Even with zero coverage, should be marked past.
      final result =
          planRoutineEdges([slot], [], day: earlierDay, now: testNow);

      expect(result[9]!.isPast, true);
      expect(result[9]!.verdict, RoutineVerdict.red); // Zero coverage → red
    });

    test('summed coverage can exceed 1.0 → still green with match', () {
      final slot = (startHour: 9, durationHours: 1, categoryId: 1);
      // Slot: 9:00–10:00 (60 min).
      // Two logs, each covering the full hour (total 120 min, coverage = 2.0).
      final log1 = (
        start: DateTime(2026, 8, 27, 9, 0),
        end: DateTime(2026, 8, 27, 10, 0),
        categoryId: 1,
      );
      final log2 = (
        start: DateTime(2026, 8, 27, 9, 0),
        end: DateTime(2026, 8, 27, 10, 0),
        categoryId: 1,
      );
      final now = DateTime(2026, 8, 27, 11, 0);
      final result =
          planRoutineEdges([slot], [log1, log2], day: testDay, now: now);

      expect(result[9]!.verdict, RoutineVerdict.green);
    });

    test('first-by-startHour wins on collision', () {
      final slot1 = (startHour: 9, durationHours: 2, categoryId: 1);
      final slot2 = (startHour: 10, durationHours: 1, categoryId: 2);
      // Both cover hour 10. Slot1 (startHour=9) should win.
      final result = planRoutineEdges(
        [slot1, slot2],
        [],
        day: testDay,
        now: DateTime(2026, 8, 27, 11, 0),
      );

      // Hour 9: only slot1.
      expect(result[9], isNotNull);
      // Hour 10: slot1 wins (earlier startHour).
      expect(result[10]!.verdict, result[9]!.verdict);
    });

    test('null categoryId on slot can match null categoryId on log', () {
      final slot = (startHour: 9, durationHours: 1, categoryId: null);
      final log = (
        start: DateTime(2026, 8, 27, 9, 0),
        end: DateTime(2026, 8, 27, 10, 0),
        categoryId: null,
      );
      final now = DateTime(2026, 8, 27, 11, 0);
      final result =
          planRoutineEdges([slot], [log], day: testDay, now: now);

      // Coverage 1.0, category match (both null).
      expect(result[9]!.verdict, RoutineVerdict.green);
    });

    test('cross-midnight log clipped to day boundaries', () {
      final slot = (startHour: 0, durationHours: 2, categoryId: 1);
      // Slot: 0:00–2:00. Log spans midnight (yesterday 23:00 to today 1:00).
      final log = (
        start: DateTime(2026, 8, 26, 23, 0),
        end: DateTime(2026, 8, 27, 1, 0),
        categoryId: 1,
      );
      final now = DateTime(2026, 8, 27, 3, 0);
      final result =
          planRoutineEdges([slot], [log], day: testDay, now: now);

      // Log is clipped to 0:00–1:00 on testDay (60 min).
      // Slot is 0:00–2:00 (120 min). Coverage = 60/120 = 0.5.
      expect(result[0]!.verdict, RoutineVerdict.amber);
      expect(result[1]!.verdict, RoutineVerdict.amber);
    });

    test('slot at boundary startHour=23, durationHours=1 fills hour 23', () {
      final slot = (startHour: 23, durationHours: 1, categoryId: 1);
      final result = planRoutineEdges([slot], [], day: testDay, now: testNow);

      expect(result[22], null);
      expect(result[23], isNotNull);
      expect(result.length, 24);
    });

    test('slot extending past 24 hours (startHour=22, duration=3) clamps to hour 23', () {
      final slot = (startHour: 22, durationHours: 3, categoryId: 1);
      // Would cover hours 22, 23, 24 (25), but clamped to 0–24.
      final result = planRoutineEdges([slot], [], day: testDay, now: testNow);

      expect(result[21], null);
      expect(result[22], isNotNull);
      expect(result[23], isNotNull);
      expect(result.length, 24);
    });
  });
}
