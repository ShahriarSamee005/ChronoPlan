import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import 'database_provider.dart';

/// Midnight-normalized day key, used consistently everywhere a "which day"
/// value is needed for task data.
DateTime normalizeDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// The single source of truth for "what day is it, for task purposes."
/// Card/sheet/debrief all read this instead of calling DateTime.now()
/// independently — that split-brain (each computing "today" a millisecond
/// apart, or not at all after a resume) is exactly what caused tasks to
/// vanish across a midnight rollover in a resident app. Flipped by the
/// lifecycle observer in AppShell on resume; initialized to today here.
final currentDayProvider =
    StateProvider<DateTime>((ref) => normalizeDay(DateTime.now()));

/// Not-done tasks for the given day, in insertion order. Callers must pass
/// an already-normalized midnight [dayKey] — this provider does not call
/// DateTime.now() itself, so it can't go stale across a midnight rollover
/// while the app stays resident (see rollForwardProvider's doc comment).
final dayTasksProvider =
    StreamProvider.family<List<IntentionTask>, DateTime>((ref, dayKey) {
  return ref.watch(appDatabaseProvider).intentionTasksDao.watchForDay(dayKey);
});

/// Rolls yesterday-and-earlier open tasks onto [day]. Keyed by day so it
/// naturally re-runs if the app session crosses midnight, and stays cached
/// (no repeat writes) for the rest of that day.
final rollForwardProvider = FutureProvider.family<void, DateTime>((ref, day) {
  final dayKey = normalizeDay(day);
  return ref.watch(appDatabaseProvider).intentionTasksDao.rollForward(dayKey);
});

/// (doneCount, totalCount) for [dayKey]. Re-runs whenever
/// dayTasksProvider(dayKey) emits — i.e. on every add/done/remove that
/// touches that day's tasks — so it stays reactive without any manual
/// invalidation. Same normalized-dayKey contract as dayTasksProvider.
final taskCountsProvider =
    FutureProvider.family<(int, int), DateTime>((ref, dayKey) async {
  ref.watch(dayTasksProvider(dayKey));
  final dao = ref.watch(appDatabaseProvider).intentionTasksDao;
  final done = await dao.countDoneForDay(dayKey);
  final total = await dao.countTotalForDay(dayKey);
  return (done, total);
});
