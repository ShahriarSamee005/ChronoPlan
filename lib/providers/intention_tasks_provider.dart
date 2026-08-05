import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import 'database_provider.dart';

/// Not-done tasks for today, in insertion order.
final dayTasksProvider = StreamProvider<List<IntentionTask>>((ref) {
  final today = DateTime.now();
  return ref.watch(appDatabaseProvider).intentionTasksDao.watchForDay(today);
});

/// Rolls yesterday-and-earlier open tasks onto today. Keyed by day so it
/// naturally re-runs if the app session crosses midnight, and stays cached
/// (no repeat writes) for the rest of that day.
final rollForwardProvider = FutureProvider.family<void, DateTime>((ref, day) {
  final dayKey = DateTime(day.year, day.month, day.day);
  return ref.watch(appDatabaseProvider).intentionTasksDao.rollForward(dayKey);
});

/// (doneCount, totalCount) for today. Re-runs whenever [dayTasksProvider]
/// emits — i.e. on every add/done/remove that touches today's tasks — so it
/// stays reactive without any manual invalidation.
final taskCountsProvider = FutureProvider<(int, int)>((ref) async {
  ref.watch(dayTasksProvider);
  final dao = ref.watch(appDatabaseProvider).intentionTasksDao;
  final today = DateTime.now();
  final done = await dao.countDoneForDay(today);
  final total = await dao.countTotalForDay(today);
  return (done, total);
});
