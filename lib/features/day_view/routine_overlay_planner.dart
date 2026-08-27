/// Pure per-hour routine verdict and edge logic for Day View overlay.
///
/// Kept free of Flutter/Drift imports so it is directly unit-testable. Callers
/// map their RoutineSlots and LogEntries onto [PlanSlot] and [PlanLog] records
/// before calling in.
library;

/// One routine slot to lay out, reduced to what the verdict actually needs.
typedef PlanSlot = ({int startHour, int durationHours, int? categoryId});

/// One log entry to check against, reduced to time range and category.
typedef PlanLog = ({DateTime start, DateTime end, int? categoryId});

/// Verdict on how well a routine slot was covered.
enum RoutineVerdict { green, amber, red, neutral }

/// The verdict and past-ness of a routine slot in a single hour.
typedef HourRoutine = ({
  RoutineVerdict verdict,
  bool isPast,
  int? categoryId, // Slot's categoryId, for color lookup
});

const int _minutesPerHour = 60;

/// Computes routine slot verdicts for each hour of [day].
///
/// Returns exactly 24 elements, index = hour 0..23. Each element is null if no
/// slot covers that hour, or `HourRoutine` with the verdict and past-ness of
/// the slot covering that hour. If two slots cover the same hour, the one with
/// the smaller [startHour] wins (documented below).
///
/// Logic:
/// - Coverage = (sum of minutes each log overlaps the slot window) / (slot duration in minutes).
///   Can exceed 1.0 if logs overlap each other within the slot. Logs are clipped
///   to [dayStart, dayEnd) first.
/// - Category match = any log overlapping the slot has `categoryId == slot.categoryId`.
///   If slot.categoryId is null, match is only true if some log has categoryId == null.
/// - isPast: For [day]'s date:
///   - Earlier than [now]'s date → true
///   - Same date as [now] → true if slot end time ≤ now's time, else false
///   - Later than [now]'s date → false
/// - Verdict (once isPast is known):
///   - not isPast → neutral (slot hasn't happened yet)
///   - isPast && coverage ≥ 0.75 && categoryMatch → green
///   - isPast && coverage ≥ 0.10 → amber (even without match)
///   - isPast && coverage < 0.10 → red
///
/// Assumptions: slots are already filtered to isActive=true and applicable to
/// [day]'s weekday. Logs include all entries for [day] with cross-midnight ones
/// clipped to the day.
List<HourRoutine?> planRoutineEdges(
  List<PlanSlot> slots,
  List<PlanLog> logs, {
  required DateTime day,
  required DateTime now,
}) {
  final result = List<HourRoutine?>.filled(24, null);

  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  for (final slot in slots) {
    final routine = _slotRoutine(slot, logs, dayStart, dayEnd, now);

    // Fill all hours in [startHour, startHour + durationHours)
    final endHour = (slot.startHour + slot.durationHours).clamp(0, 24);
    for (var h = slot.startHour; h < endHour && h < 24; h++) {
      // First slot wins if two collide on an hour (smaller startHour).
      if (result[h] == null) {
        result[h] = routine;
      }
    }
  }

  return result;
}

HourRoutine _slotRoutine(
  PlanSlot slot,
  List<PlanLog> logs,
  DateTime dayStart,
  DateTime dayEnd,
  DateTime now,
) {
  final slotStartMin = slot.startHour * _minutesPerHour;
  final slotEndMin = (slot.startHour + slot.durationHours) * _minutesPerHour;

  // Determine if the slot is in the past, present, or future.
  final dayDate = DateTime(dayStart.year, dayStart.month, dayStart.day);
  final nowDate = DateTime(now.year, now.month, now.day);

  late final bool isPast;
  if (dayDate.isBefore(nowDate)) {
    isPast = true;
  } else if (dayDate.isAfter(nowDate)) {
    isPast = false;
  } else {
    // Same day: compare slot end time with current time in minutes from midnight.
    final nowMinute = now.hour * _minutesPerHour + now.minute;
    isPast = slotEndMin <= nowMinute;
  }

  if (!isPast) {
    return (verdict: RoutineVerdict.neutral, isPast: false, categoryId: slot.categoryId);
  }

  // Compute coverage: sum of overlaps / slot duration.
  int totalOverlapMin = 0;
  for (final log in logs) {
    // Clip log to the day first.
    final logStart = log.start.isBefore(dayStart) ? dayStart : log.start;
    final logEnd = log.end.isAfter(dayEnd) ? dayEnd : log.end;

    // Compute overlap in minutes from midnight within the day.
    final logStartMin = logStart.difference(dayStart).inMinutes;
    final logEndMin = logEnd.difference(dayStart).inMinutes;

    final overlapStart = logStartMin > slotStartMin ? logStartMin : slotStartMin;
    final overlapEnd = logEndMin < slotEndMin ? logEndMin : slotEndMin;

    if (overlapEnd > overlapStart) {
      totalOverlapMin += overlapEnd - overlapStart;
    }
  }

  final slotDurationMin = slotEndMin - slotStartMin;
  final coverage =
      slotDurationMin > 0 ? totalOverlapMin / slotDurationMin : 0.0;

  // Check category match: any log overlapping the slot with matching categoryId.
  bool categoryMatch = false;
  for (final log in logs) {
    if (log.categoryId != slot.categoryId) continue;

    final logStart = log.start.isBefore(dayStart) ? dayStart : log.start;
    final logEnd = log.end.isAfter(dayEnd) ? dayEnd : log.end;

    final logStartMin = logStart.difference(dayStart).inMinutes;
    final logEndMin = logEnd.difference(dayStart).inMinutes;

    if (logStartMin < slotEndMin && logEndMin > slotStartMin) {
      categoryMatch = true;
      break;
    }
  }

  // Compute verdict.
  late final RoutineVerdict verdict;
  if (coverage >= 0.75 && categoryMatch) {
    verdict = RoutineVerdict.green;
  } else if (coverage >= 0.10) {
    verdict = RoutineVerdict.amber;
  } else {
    verdict = RoutineVerdict.red;
  }

  return (verdict: verdict, isPast: true, categoryId: slot.categoryId);
}
