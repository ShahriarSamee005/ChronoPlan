import 'package:chronoplan/features/day_view/hour_row_planner.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime day = DateTime(2026, 8, 24);

PlanEntry entry(int id, DateTime start, DateTime end) =>
    (entryId: id, start: start, end: end);

DateTime at(int hour, [int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// Asserts the guarantees documented on [planHourRows] across every hour.
void expectInvariants(List<List<HourSegment>> rows) {
  expect(rows.length, 24, reason: 'planHourRows must return exactly 24 rows');

  final firstCounts = <int, int>{};
  final lastCounts = <int, int>{};

  for (var h = 0; h < 24; h++) {
    final segments = rows[h];
    final laneEnds = <int, int>{};

    for (final s in segments) {
      expect(s.startMin, greaterThanOrEqualTo(0),
          reason: 'hour $h: startMin below 0');
      expect(s.endMin, greaterThan(s.startMin),
          reason: 'hour $h: endMin <= startMin');
      expect(s.endMin, lessThanOrEqualTo(60),
          reason: 'hour $h: endMin past the hour');

      expect(s.laneCount, greaterThanOrEqualTo(1),
          reason: 'hour $h: laneCount below 1');
      expect(s.lane, greaterThanOrEqualTo(0), reason: 'hour $h: lane below 0');
      expect(s.lane, lessThan(s.laneCount),
          reason: 'hour $h: lane outside laneCount');
      expect(s.laneCount, segments.first.laneCount,
          reason: 'hour $h: laneCount differs within the hour');

      // Segments sharing a lane must not overlap. The hour comes back in start
      // order, so comparing against that lane's previous end is enough.
      final prevEnd = laneEnds[s.lane];
      if (prevEnd != null) {
        expect(prevEnd, lessThanOrEqualTo(s.startMin),
            reason: 'hour $h: lane ${s.lane} overlaps itself');
      }
      laneEnds[s.lane] = s.endMin;

      if (s.isFirstOfEntry) {
        firstCounts[s.entryId] = (firstCounts[s.entryId] ?? 0) + 1;
      }
      if (s.isLastOfEntry) {
        lastCounts[s.entryId] = (lastCounts[s.entryId] ?? 0) + 1;
      }
    }
  }

  final ids = {...firstCounts.keys, ...lastCounts.keys};
  for (final id in ids) {
    expect(firstCounts[id], 1, reason: 'entry $id: not exactly one first hour');
    expect(lastCounts[id], 1, reason: 'entry $id: not exactly one last hour');
  }
}

/// Flattens to `hour -> [(startMin, endMin)]` for the hours that have segments.
Map<int, List<(int, int)>> occupied(List<List<HourSegment>> rows) {
  final out = <int, List<(int, int)>>{};
  for (var h = 0; h < 24; h++) {
    if (rows[h].isEmpty) continue;
    out[h] = [for (final s in rows[h]) (s.startMin, s.endMin)];
  }
  return out;
}

void main() {
  test('returns 24 rows for an empty day', () {
    final rows = planHourRows(const [], day: day);

    expect(rows.length, 24);
    expect(rows.every((r) => r.isEmpty), isTrue);
    expectInvariants(rows);
  });

  test('full-hour entry fills exactly its own hour', () {
    final rows = planHourRows([entry(1, at(8), at(9))], day: day);

    expect(occupied(rows), {
      8: [(0, 60)]
    });
    final s = rows[8].single;
    expect(s.entryId, 1);
    expect(s.isFirstOfEntry, isTrue);
    expect(s.isLastOfEntry, isTrue);
    expect(s.lane, 0);
    expect(s.laneCount, 1);
    expectInvariants(rows);
  });

  test('entry ending exactly on the hour does not spill into the next hour',
      () {
    final rows = planHourRows([entry(1, at(8), at(9))], day: day);

    expect(rows[9], isEmpty);
    expectInvariants(rows);
  });

  test('half-hour entry occupies the first half of its hour', () {
    final rows = planHourRows([entry(1, at(8), at(8, 30))], day: day);

    expect(occupied(rows), {
      8: [(0, 30)]
    });
    expectInvariants(rows);
  });

  test('mid-hour entry keeps its offsets', () {
    final rows = planHourRows([entry(1, at(8, 20), at(8, 50))], day: day);

    expect(occupied(rows), {
      8: [(20, 50)]
    });
    expect(rows[8].single.isFirstOfEntry, isTrue);
    expect(rows[8].single.isLastOfEntry, isTrue);
    expectInvariants(rows);
  });

  test('multi-hour entry slices across every hour it touches', () {
    final rows = planHourRows([entry(1, at(8, 20), at(10, 40))], day: day);

    expect(occupied(rows), {
      8: [(20, 60)],
      9: [(0, 60)],
      10: [(0, 40)],
    });

    expect(rows[8].single.isFirstOfEntry, isTrue);
    expect(rows[8].single.isLastOfEntry, isFalse);
    expect(rows[9].single.isFirstOfEntry, isFalse);
    expect(rows[9].single.isLastOfEntry, isFalse);
    expect(rows[10].single.isFirstOfEntry, isFalse);
    expect(rows[10].single.isLastOfEntry, isTrue);

    for (final h in [8, 9, 10]) {
      expect(rows[h].single.laneCount, 1, reason: 'hour $h should need 1 lane');
    }
    expectInvariants(rows);
  });

  test('entry crossing midnight contributes only its in-day portion', () {
    final rows = planHourRows(
      [entry(1, at(23), DateTime(2026, 8, 25, 1))],
      day: day,
    );

    expect(occupied(rows), {
      23: [(0, 60)]
    });
    expect(rows[23].single.isFirstOfEntry, isTrue);
    expect(rows[23].single.isLastOfEntry, isTrue);
    expectInvariants(rows);
  });

  test('entry arriving from the previous day is clipped at midnight', () {
    final rows = planHourRows(
      [entry(1, DateTime(2026, 8, 23, 22), at(1, 30))],
      day: day,
    );

    expect(occupied(rows), {
      0: [(0, 60)],
      1: [(0, 30)],
    });
    expect(rows[0].single.isFirstOfEntry, isTrue);
    expect(rows[1].single.isLastOfEntry, isTrue);
    expectInvariants(rows);
  });

  test('degenerate and inverted entries are dropped', () {
    final rows = planHourRows([
      entry(1, at(10), at(10)),
      entry(2, at(10, 30), at(10)),
    ], day: day);

    expect(occupied(rows), isEmpty);
    expectInvariants(rows);
  });

  test('an entry on another day is dropped', () {
    final rows = planHourRows(
      [entry(1, DateTime(2026, 8, 22, 9), DateTime(2026, 8, 22, 10))],
      day: day,
    );

    expect(occupied(rows), isEmpty);
    expectInvariants(rows);
  });

  test('overlapping entries in one hour get separate lanes', () {
    final rows = planHourRows([
      entry(1, at(8), at(8, 40)),
      entry(2, at(8, 20), at(9)),
    ], day: day);

    expect(rows[8].length, 2);
    expect(rows[8].every((s) => s.laneCount == 2), isTrue);
    expect(rows[8].map((s) => s.lane).toSet(), {0, 1});

    final byId = {for (final s in rows[8]) s.entryId: s};
    expect((byId[1]!.startMin, byId[1]!.endMin), (0, 40));
    expect((byId[2]!.startMin, byId[2]!.endMin), (20, 60));
    expect(byId[1]!.lane == byId[2]!.lane, isFalse,
        reason: 'overlapping segments must not share a lane');

    expectInvariants(rows);
  });

  test('back-to-back entries in one hour share a single lane', () {
    final rows = planHourRows([
      entry(1, at(8), at(8, 30)),
      entry(2, at(8, 30), at(9)),
    ], day: day);

    expect(rows[8].length, 2);
    expect(rows[8].every((s) => s.lane == 0 && s.laneCount == 1), isTrue);
    expectInvariants(rows);
  });

  test('laneCount is per hour, not per day', () {
    final rows = planHourRows([
      entry(1, at(8), at(10)), // spans both hours
      entry(2, at(8, 15), at(8, 45)), // overlaps only inside hour 8
    ], day: day);

    expect(rows[8].every((s) => s.laneCount == 2), isTrue);
    expect(rows[9].single.laneCount, 1);
    expectInvariants(rows);
  });

  test('holds every invariant across a mixed fixture', () {
    final rows = planHourRows([
      entry(1, DateTime(2026, 8, 23, 23), at(6, 45)), // sleep from yesterday
      entry(2, at(6, 45), at(7, 20)),
      entry(3, at(7), at(7, 30)), // overlaps 2
      entry(4, at(7, 10), at(7, 15)), // overlaps 2 and 3
      entry(5, at(9), at(9)), // degenerate
      entry(6, at(12, 30), at(12)), // inverted
      entry(7, at(13, 5), at(16, 55)),
      entry(8, at(16), at(17)), // overlaps 7
      entry(9, at(23, 30), DateTime(2026, 8, 25, 7)), // crosses midnight
      entry(10, DateTime(2026, 8, 25, 8), DateTime(2026, 8, 25, 9)), // next day
    ], day: day);

    expectInvariants(rows);

    // The dropped rows contribute nothing at all.
    final seenIds = {
      for (final row in rows)
        for (final s in row) s.entryId
    };
    expect(seenIds.contains(5), isFalse);
    expect(seenIds.contains(6), isFalse);
    expect(seenIds.contains(10), isFalse);

    // Yesterday's sleep starts at midnight and ends mid-hour-6.
    expect(rows[0].single.entryId, 1);
    expect((rows[0].single.startMin, rows[0].single.endMin), (0, 60));
    expect(rows[0].single.isFirstOfEntry, isTrue);
    expect(rows[6].firstWhere((s) => s.entryId == 1).endMin, 45);

    // The three-way overlap in hour 7 needs three lanes.
    expect(rows[7].length, 3);
    expect(rows[7].every((s) => s.laneCount == 3), isTrue);

    // Hour 17 stays empty: entry 8 ends exactly on the boundary.
    expect(rows[17], isEmpty);

    // The midnight crosser stops at the end of the day.
    expect((rows[23].single.startMin, rows[23].single.endMin), (30, 60));
    expect(rows[23].single.isLastOfEntry, isTrue);
  });
}
