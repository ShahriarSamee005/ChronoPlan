import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/usage_stats/carve_proposal.dart';
import 'database_provider.dart';
import 'log_entries_provider.dart';
import 'usage_stats_provider.dart';

export '../core/usage_stats/carve_proposal.dart' show CarveProposal;

// Private: DB-backed stream of dismissed carves for today.
final _dismissedCarvesTodayProvider = StreamProvider<List<DismissedCarve>>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .dismissedCarvesDao
      .watchForDate(DateTime.now());
});

/// Derives pending carve proposals for TODAY by combining:
///   • Hourly OS usage   ([hourlyUsageForTodayProvider])
///   • Today's log entries ([logEntriesForDayProvider])
///   • Per-app dismissals  ([_dismissedCarvesTodayProvider])
///
/// A carve proposal is generated for an elapsed hour bucket when:
///   1. Exactly ONE logged entry is fully contained within the bucket
///      (entry.startTime >= bucketStart && entry.endTime <= bucketEnd), and it
///      is user-origin — a screen-time row (isUsageDerived) is never a carve
///      target, since there is nothing to reattribute out of it.
///      Buckets with zero entries are handled by Phase 2a (empty-bucket card).
///      Buckets with >1 entries are skipped — multi-entry carving is future scope.
///   2. An app has >= 10 minutes of foreground usage in that bucket.
///   3. The app's display name does NOT appear (case-insensitive) in the
///      logged entry's description — auto-suppress if already noted by user.
///   4. The user has not dismissed this (date, hour, packageName) triple.
///
/// Proposals are sorted by hour asc, then by duration desc within the same hour.
final carveProposalsProvider =
    Provider<AsyncValue<List<CarveProposal>>>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final hourlyAsync = ref.watch(hourlyUsageForTodayProvider);
  // Always watch today's entries directly; don't rely on selectedDateProvider.
  final entriesAsync = ref.watch(logEntriesForDayProvider(today));
  final dismissedAsync = ref.watch(_dismissedCarvesTodayProvider);

  if (hourlyAsync is AsyncLoading ||
      entriesAsync is AsyncLoading ||
      dismissedAsync is AsyncLoading) {
    return const AsyncValue.loading();
  }
  // Degrade gracefully on any error — proposals simply won't appear.
  if (hourlyAsync.hasError || entriesAsync.hasError || dismissedAsync.hasError) {
    return const AsyncValue.data([]);
  }

  final hourly = hourlyAsync.value!;
  final entries = entriesAsync.value!;
  final dismissed = dismissedAsync.value!;

  // Build a quick lookup set: "hour:packageName"
  final dismissedSet =
      dismissed.map((d) => '${d.bucketHour}:${d.packageName}').toSet();

  final proposals = <CarveProposal>[];

  for (int h = 0; h < now.hour; h++) {
    final bucketStart = today.add(Duration(hours: h));
    final bucketEnd = bucketStart.add(const Duration(hours: 1));

    // Only qualify buckets where exactly one entry is FULLY within this hour.
    // This avoids the complexity of carving sub-sections from multi-hour entries.
    final bucketEntries = entries
        .where((e) =>
            !e.startTime.isBefore(bucketStart) &&
            !e.endTime.isAfter(bucketEnd))
        .toList();

    if (bucketEntries.length != 1) continue;
    // Never carve a screen-time block: it is already OS-derived, so there is
    // nothing to reattribute, and trimming it would falsify the record.
    if (bucketEntries.first.isUsageDerived) continue;
    final loggedEntry = bucketEntries.first;

    final apps = hourly[h] ?? [];
    final entryDurationMinutes =
        loggedEntry.endTime.difference(loggedEntry.startTime).inMinutes;
    if (entryDurationMinutes <= 0) continue;

    for (final app in apps) {
      // Minimum-duration threshold is enforced once, in
      // UsageStatsService._sliceByHour — apps below it never reach `hourly`.

      // Auto-suppress: if the user already described this app in the entry.
      if (loggedEntry.description
          .toLowerCase()
          .contains(app.appLabel.toLowerCase())) {
        continue;
      }

      if (dismissedSet.contains('$h:${app.packageName}')) { continue; }

      // Cap against the hour, not the entry: the confirm path places the FULL
      // detected minutes in the hour's empty space and only trims the logged
      // entry if the hour would exceed 60 (see planCarve).
      final cappedMinutes = app.durationMinutes.clamp(0, 60);
      if (cappedMinutes <= 0) { continue; }

      proposals.add(CarveProposal(
        hour: h,
        loggedEntry: loggedEntry,
        packageName: app.packageName,
        appLabel: app.appLabel,
        durationMinutes: cappedMinutes,
      ));
    }
  }

  proposals.sort((a, b) {
    final hourCmp = a.hour.compareTo(b.hour);
    if (hourCmp != 0) { return hourCmp; }
    return b.durationMinutes.compareTo(a.durationMinutes);
  });

  return AsyncValue.data(proposals);
});
