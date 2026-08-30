/// Pure adapter: hour-based routine slots → [PlanEntry] input for the shared
/// [planHourRows] slicing used by `HourTimeline`.
///
/// Kept free of Flutter/Drift imports so it is directly unit-testable and can be
/// reused wherever routine slots are drawn. Callers map their DB `RoutineSlot`
/// rows onto the plain `({int id, int startHour, int durationHours})` record
/// before calling in.
library;

import '../day_view/hour_row_planner.dart';

/// Turns hour-based [slots] into planner entries anchored to [day].
///
/// Each slot becomes a [PlanEntry] running from `startHour:00` for
/// `durationHours` whole hours:
/// `start = DateTime(day.., startHour)`, `end = start + durationHours hours`.
///
/// No clipping happens here on purpose — a slot whose end crosses midnight (e.g.
/// `startHour: 23, durationHours: 3`) keeps a raw end on the NEXT day, and
/// [planHourRows] is left to clip it to `[dayStart, dayEnd)`. The practical
/// effect is that such a slot shows only in its in-day rows after planning (the
/// 23:00 row for that example) rather than wrapping to the top of the day. This
/// replaces the old vertical-Stack overflow behaviour and is acceptable.
List<PlanEntry> slotsToPlanEntries(
  List<({int id, int startHour, int durationHours})> slots, {
  required DateTime day,
}) {
  return slots.map((s) {
    final start = DateTime(day.year, day.month, day.day, s.startHour);
    final end = start.add(Duration(hours: s.durationHours));
    return (entryId: s.id, start: start, end: end);
  }).toList();
}
