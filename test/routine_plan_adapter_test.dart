import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/features/day_view/hour_row_planner.dart';
import 'package:chronoplan/features/routine/routine_plan_adapter.dart';

// Pure unit tests for the hour-slot → PlanEntry adapter and its interaction with
// planHourRows. No Flutter/Drift surface — this is straight Dart.

void main() {
  final day = DateTime(2026, 8, 30); // a fixed reference day

  test('a 1h slot maps to a single-hour PlanEntry with correct start/end', () {
    final entries = slotsToPlanEntries(
      [(id: 1, startHour: 9, durationHours: 1)],
      day: day,
    );

    expect(entries, hasLength(1));
    expect(entries.single.entryId, 1);
    expect(entries.single.start, DateTime(2026, 8, 30, 9));
    expect(entries.single.end, DateTime(2026, 8, 30, 10));

    // And planHourRows yields exactly one full-hour segment in the 09:00 row.
    final rows = planHourRows(entries, day: day);
    expect(rows[9], hasLength(1));
    final seg = rows[9].single;
    expect(seg.entryId, 1);
    expect(seg.startMin, 0);
    expect(seg.endMin, 60);
    expect(seg.isFirstOfEntry, isTrue);
    expect(seg.isLastOfEntry, isTrue);
    // Every other hour is empty.
    for (var h = 0; h < 24; h++) {
      if (h != 9) expect(rows[h], isEmpty, reason: 'hour $h should be empty');
    }
  });

  test('a 4h slot maps to a 4-hour span and slices into 4 continuous rows', () {
    final entries = slotsToPlanEntries(
      [(id: 7, startHour: 9, durationHours: 4)],
      day: day,
    );

    expect(entries.single.start, DateTime(2026, 8, 30, 9));
    expect(entries.single.end, DateTime(2026, 8, 30, 13));

    final rows = planHourRows(entries, day: day);
    // Present in 9, 10, 11, 12; absent at 13.
    for (final h in [9, 10, 11, 12]) {
      expect(rows[h], hasLength(1), reason: 'hour $h should carry the slot');
      expect(rows[h].single.entryId, 7);
    }
    expect(rows[13], isEmpty);
    // First/last flags land on the outer rows only → continuous bar.
    expect(rows[9].single.isFirstOfEntry, isTrue);
    expect(rows[9].single.isLastOfEntry, isFalse);
    expect(rows[12].single.isFirstOfEntry, isFalse);
    expect(rows[12].single.isLastOfEntry, isTrue);
  });

  test('two overlapping slots in one hour lane-stack into 2 lanes', () {
    final entries = slotsToPlanEntries(
      [
        (id: 1, startHour: 14, durationHours: 1),
        (id: 2, startHour: 14, durationHours: 1),
      ],
      day: day,
    );

    final rows = planHourRows(entries, day: day);
    expect(rows[14], hasLength(2));
    // Both report a laneCount of 2 and occupy distinct lanes 0 and 1.
    expect(rows[14].map((s) => s.laneCount).toSet(), {2});
    expect(rows[14].map((s) => s.lane).toSet(), {0, 1});
  });

  test('a midnight-crossing slot keeps a next-day raw end but plans in-day only',
      () {
    final entries = slotsToPlanEntries(
      [(id: 5, startHour: 23, durationHours: 3)],
      day: day,
    );

    // The adapter does NOT clip: raw end is 02:00 on the NEXT day.
    expect(entries.single.start, DateTime(2026, 8, 30, 23));
    expect(entries.single.end, DateTime(2026, 8, 31, 2));

    // planHourRows clips to the day: only the 23:00 row carries a segment.
    final rows = planHourRows(entries, day: day);
    expect(rows[23], hasLength(1));
    expect(rows[23].single.startMin, 0);
    expect(rows[23].single.endMin, 60);
    expect(rows[23].single.isFirstOfEntry, isTrue);
    expect(rows[23].single.isLastOfEntry, isTrue);
    // Nothing wraps to the top of the day.
    expect(rows[0], isEmpty);
    expect(rows[1], isEmpty);
  });

  test('empty input yields no entries', () {
    expect(slotsToPlanEntries(const [], day: day), isEmpty);
  });
}
