/// Pure once-a-day gate for the usage-analytics ping.
///
/// Kept free of Flutter/Drift imports so it is directly unit-testable, matching
/// the style of `current_slot_planner.dart`. Callers parse their stored
/// `lastSyncedAt` string into a [DateTime] before calling in.
library;

/// Whether an analytics ping is due.
///
/// Returns true when [lastPing] is null, or when [lastPing] falls on an earlier
/// calendar day than [now]. Returns false when they land on the same calendar
/// day. The comparison is by calendar day, not elapsed hours — a ping at 23:00
/// yesterday is due again at 00:30 today, and one at 00:30 today is not due
/// again at 23:00 the same day.
bool shouldPing({required DateTime? lastPing, required DateTime now}) {
  if (lastPing == null) return true;
  final lastDay = DateTime(lastPing.year, lastPing.month, lastPing.day);
  final nowDay = DateTime(now.year, now.month, now.day);
  return nowDay.isAfter(lastDay);
}
