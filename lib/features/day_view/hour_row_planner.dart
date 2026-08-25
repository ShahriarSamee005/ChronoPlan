/// Pure per-hour slicing math for the row-based Day View.
///
/// Kept free of Flutter/Drift imports so it is directly unit-testable — see
/// `test/hour_row_planner_test.dart`. The DB row type stays out on purpose:
/// callers map their entries onto [PlanEntry] before calling in.
library;

/// One entry to lay out, reduced to what the slicing actually needs.
typedef PlanEntry = ({int entryId, DateTime start, DateTime end});

/// One entry's slice of a single hour row.
typedef HourSegment = ({
  int entryId,
  int startMin, // 0..59  offset within the hour
  int endMin, // 1..60  offset within the hour (endMin > startMin)
  bool isFirstOfEntry, // this is the entry's earliest visible hour today
  bool isLastOfEntry, // this is the entry's latest visible hour today
  int lane, // 0-based lane within the hour (overlap resolution)
  int laneCount, // total lanes used in this hour (>=1)
});

const int _minutesPerHour = 60;
const int _minutesPerDay = 24 * _minutesPerHour;

/// Slices [entries] into per-hour segments for [day].
///
/// Returns exactly 24 lists, index = hour 0..23, each holding that hour's
/// segments sorted by [HourSegment.startMin] (longer first on a tie).
///
/// Entries are clipped to `[dayStart, dayEnd)` before slicing, so an entry that
/// crosses midnight contributes only its in-day portion — that is what keeps a
/// sleep block from painting a sliver at the top of the next day. Entries that
/// survive with less than a whole minute inside the day are dropped, as are
/// degenerate (`end <= start`) rows.
///
/// Guarantees on every emitted segment: `0 <= startMin < endMin <= 60`,
/// `0 <= lane < laneCount`, `laneCount >= 1`, no two segments share a lane
/// within an hour while overlapping, and each surviving entry carries exactly
/// one [HourSegment.isFirstOfEntry] and one [HourSegment.isLastOfEntry].
List<List<HourSegment>> planHourRows(
  List<PlanEntry> entries, {
  required DateTime day,
}) {
  final dayStart = DateTime(day.year, day.month, day.day);

  // Everything below is integer minutes from midnight, which keeps the hour
  // boundaries exact and the slicing free of DateTime rounding surprises.
  final buckets = List.generate(24, (_) => <_Slice>[], growable: false);

  for (final entry in entries) {
    final rawStart = entry.start.difference(dayStart).inMinutes;
    final rawEnd = entry.end.difference(dayStart).inMinutes;

    // Clip to the day; drop anything that doesn't leave a whole minute inside
    // it (covers inverted/degenerate rows and other days' entries alike).
    final startMin = rawStart < 0 ? 0 : rawStart;
    final endMin = rawEnd > _minutesPerDay ? _minutesPerDay : rawEnd;
    if (endMin <= startMin) continue;

    final firstHour = startMin ~/ _minutesPerHour;
    // An entry ending exactly on an hour boundary does not occupy the next hour.
    final lastHour = (endMin - 1) ~/ _minutesPerHour;

    for (var h = firstHour; h <= lastHour; h++) {
      final hourStart = h * _minutesPerHour;
      final segStart = startMin > hourStart ? startMin : hourStart;
      final hourEnd = hourStart + _minutesPerHour;
      final segEnd = endMin < hourEnd ? endMin : hourEnd;
      if (segEnd <= segStart) continue;

      buckets[h].add(_Slice(
        entryId: entry.entryId,
        startMin: segStart - hourStart,
        endMin: segEnd - hourStart,
        isFirstOfEntry: h == firstHour,
        isLastOfEntry: h == lastHour,
      ));
    }
  }

  return List.generate(24, (h) => _assignLanes(buckets[h]), growable: false);
}

/// Resolves overlaps inside one hour by packing [slices] into lanes.
///
/// Greedy first-fit over slices sorted by start (longer first on a tie), so a
/// non-overlapping hour always comes back as a single lane.
List<HourSegment> _assignLanes(List<_Slice> slices) {
  if (slices.isEmpty) return const <HourSegment>[];

  slices.sort((a, b) {
    if (a.startMin != b.startMin) return a.startMin.compareTo(b.startMin);
    final byLength = (b.endMin - b.startMin).compareTo(a.endMin - a.startMin);
    if (byLength != 0) return byLength;
    return a.entryId.compareTo(b.entryId);
  });

  final laneEnds = <int>[]; // laneEnds[i] = endMin of the last slice in lane i
  final lanes = List.filled(slices.length, 0);

  for (var i = 0; i < slices.length; i++) {
    final slice = slices[i];
    var lane = -1;
    for (var l = 0; l < laneEnds.length; l++) {
      if (laneEnds[l] <= slice.startMin) {
        lane = l;
        break;
      }
    }
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(slice.endMin);
    } else {
      laneEnds[lane] = slice.endMin;
    }
    lanes[i] = lane;
  }

  final laneCount = laneEnds.length;
  return List.generate(
    slices.length,
    (i) => (
      entryId: slices[i].entryId,
      startMin: slices[i].startMin,
      endMin: slices[i].endMin,
      isFirstOfEntry: slices[i].isFirstOfEntry,
      isLastOfEntry: slices[i].isLastOfEntry,
      lane: lanes[i],
      laneCount: laneCount,
    ),
    growable: false,
  );
}

/// A segment before its lane is known.
class _Slice {
  const _Slice({
    required this.entryId,
    required this.startMin,
    required this.endMin,
    required this.isFirstOfEntry,
    required this.isLastOfEntry,
  });

  final int entryId;
  final int startMin;
  final int endMin;
  final bool isFirstOfEntry;
  final bool isLastOfEntry;
}
