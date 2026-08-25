import 'package:chronoplan/core/database/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

/// The date the dashboard is currently showing (defaults to today).
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// All log entries for a given day, watched as a live stream.
final logEntriesForDayProvider =
    StreamProvider.family<List<LogEntry>, DateTime>((ref, date) {
  return ref.watch(appDatabaseProvider).logEntriesDao.watchForDay(date);
});

/// Day View only: entries whose range *overlaps* the day, so a cross-midnight
/// block (last night's sleep) renders on both days instead of vanishing at
/// 00:00. Deliberately separate from [logEntriesForDayProvider] — the debrief,
/// the pie chart and the carve/suggestion pipeline all still want start-of-day
/// semantics, and double-counting a crosser there would skew their totals.
final dayViewEntriesProvider =
    StreamProvider.family<List<LogEntry>, DateTime>((ref, date) {
  return ref
      .watch(appDatabaseProvider)
      .logEntriesDao
      .watchEntriesOverlappingDay(date);
});

/// Convenience: entries for the currently selected date.
final todayEntriesProvider = StreamProvider<List<LogEntry>>((ref) {
  final date = ref.watch(selectedDateProvider);
  return ref.watch(appDatabaseProvider).logEntriesDao.watchForDay(date);
});
