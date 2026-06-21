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

/// Convenience: entries for the currently selected date.
final todayEntriesProvider = StreamProvider<List<LogEntry>>((ref) {
  final date = ref.watch(selectedDateProvider);
  return ref.watch(appDatabaseProvider).logEntriesDao.watchForDay(date);
});
