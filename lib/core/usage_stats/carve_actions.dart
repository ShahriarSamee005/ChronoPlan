import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'carve_planner.dart';
import 'carve_proposal.dart';

/// What happened when a carve was applied, so the caller can surface it.
enum CarveOutcome {
  /// The entry was (re)shaped and the screen-time block(s) written.
  applied,

  /// The logged entry no longer exists — it was deleted meanwhile.
  entryMissing,

  /// The proposal carried no minutes; nothing to write.
  nothingToAdd,
}

/// Applies one carve proposal: the screen time goes into the hour's EMPTY
/// space, and the logged entry is only trimmed (from its end, never below 1
/// min) when the hour would otherwise exceed 60. It is never moved,
/// repurposed, or erased.
///
/// Placement within each gap is approximate — queryEvents gives us total
/// session duration in the bucket, not where in the hour it occurred.
///
/// Throws on database failure; callers report that to the user.
Future<CarveOutcome> applyCarve({
  required AppDatabase db,
  required CarveProposal proposal,
  required int? categoryId,
}) async {
  // Re-fetch the current entry: a previous confirm on the same entry may have
  // already shrunk it, so we must not use the stale proposal snapshot.
  final current = await db.logEntriesDao.getById(proposal.loggedEntry.id);
  if (current == null) return CarveOutcome.entryMissing;

  if (proposal.durationMinutes <= 0) return CarveOutcome.nothingToAdd;

  final hourStart = DateTime(
    current.startTime.year,
    current.startTime.month,
    current.startTime.day,
    current.startTime.hour,
  );
  final plan = planCarve(
    entryStart: current.startTime,
    entryEnd: current.endTime,
    hourStart: hourStart,
    screenMinutes: proposal.durationMinutes,
  );

  // Shrink the entry first so the freed minutes are actually free.
  if (plan.newEntryEnd != current.endTime) {
    await db.logEntriesDao.updateEntry(LogEntriesCompanion(
      id: Value(current.id),
      endTime: Value(plan.newEntryEnd),
    ));
  }
  // Insert each screen-time block through the normal retroactive path.
  for (final (blockStart, blockEnd) in plan.screenBlocks) {
    await db.logEntriesDao.insertRetroactive(
      startTime: blockStart,
      endTime: blockEnd,
      categoryId: categoryId,
      description: proposal.appLabel,
      isUsageDerived: true,
    );
  }
  return CarveOutcome.applied;
}

/// Records a (date, hour, package) dismissal so this proposal stops being
/// offered today. The dismissed-carves stream updates → carveProposalsProvider
/// recomputes → the row disappears on its own.
Future<void> dismissCarve({
  required AppDatabase db,
  required CarveProposal proposal,
}) =>
    db.dismissedCarvesDao
        .dismiss(DateTime.now(), proposal.hour, proposal.packageName);
