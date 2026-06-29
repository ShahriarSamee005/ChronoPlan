import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/usage_stats/usage_suggestion.dart';
import 'database_provider.dart';
import 'log_entries_provider.dart';
import 'usage_stats_provider.dart';

export '../core/usage_stats/usage_suggestion.dart' show UsageSuggestion;

// Private: DB-backed stream of dismissed hour-buckets for today.
final _dismissedTodayProvider = StreamProvider<List<DismissedSuggestion>>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .dismissedSuggestionsDao
      .watchForDate(DateTime.now());
});

/// Derives the list of pending usage suggestions for today by combining:
///   • Hourly usage from the OS ([hourlyUsageForTodayProvider])
///   • Existing log entries ([todayEntriesProvider])
///   • User-dismissed buckets ([_dismissedTodayProvider])
///
/// A bucket qualifies for a suggestion when ALL of the following hold:
///   1. The hour has ended (not the current or a future hour).
///   2. Total foreground usage in the bucket is >= 10 minutes.
///   3. No existing log entry overlaps the bucket window.
///   4. The user has not dismissed this bucket.
///
/// Scope: today only. Extending to recent past days is a later enhancement.
final usageSuggestionsProvider =
    Provider<AsyncValue<List<UsageSuggestion>>>((ref) {
  final hourlyAsync = ref.watch(hourlyUsageForTodayProvider);
  final entriesAsync = ref.watch(todayEntriesProvider);
  final dismissedAsync = ref.watch(_dismissedTodayProvider);

  if (hourlyAsync is AsyncLoading ||
      entriesAsync is AsyncLoading ||
      dismissedAsync is AsyncLoading) {
    return const AsyncValue.loading();
  }
  // Degrade gracefully — card simply won't appear on any error.
  if (hourlyAsync.hasError || entriesAsync.hasError || dismissedAsync.hasError) {
    return const AsyncValue.data([]);
  }

  final hourly = hourlyAsync.value!;
  final entries = entriesAsync.value!;
  final dismissedHours =
      dismissedAsync.value!.map((d) => d.bucketHour).toSet();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final suggestions = <UsageSuggestion>[];

  for (final entry in hourly.entries) {
    final hour = entry.key;
    final apps = entry.value;

    // Only suggest fully-elapsed hours (not the current or future hours).
    if (hour >= now.hour) continue;
    if (dismissedHours.contains(hour)) continue;

    final totalMinutes = apps.fold(0, (s, a) => s + a.durationMinutes);
    if (totalMinutes < 10) continue;

    final bucketStart = today.add(Duration(hours: hour));
    final bucketEnd = bucketStart.add(const Duration(hours: 1));

    // Same overlap test used by _computeMissedHours in log_entry_sheet.dart.
    final hasEntry = entries.any(
      (e) => e.startTime.isBefore(bucketEnd) && e.endTime.isAfter(bucketStart),
    );
    if (hasEntry) continue;

    // Top-3 apps by foreground duration build the suggestion description.
    final topApps = apps
        .take(3)
        .map((a) {
          final label = a.appLabel.isNotEmpty
              ? '${a.appLabel[0].toUpperCase()}${a.appLabel.substring(1)}'
              : a.appLabel;
          return '$label (${a.durationMinutes}m)';
        })
        .join(', ');

    suggestions.add(UsageSuggestion(
      hour: hour,
      bucketStart: bucketStart,
      bucketEnd: bucketEnd,
      description: topApps,
    ));
  }

  suggestions.sort((a, b) => a.hour.compareTo(b.hour));
  return AsyncValue.data(suggestions);
});
