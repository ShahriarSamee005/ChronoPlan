/// Pure placement math for the carve "accept" flow.
///
/// Kept free of Flutter/Drift imports so it is directly unit-testable — see
/// `test/plan_carve_test.dart`.
library;

/// A screen-time block to insert, as `(start, end)`.
typedef ScreenBlock = (DateTime, DateTime);

/// The outcome of planning a carve: where the logged entry now ends, and the
/// screen-time blocks to insert around it.
typedef CarvePlan = ({DateTime newEntryEnd, List<ScreenBlock> screenBlocks});

/// Plans how [screenMinutes] of screen time fit into the hour beginning at
/// [hourStart], which contains one logged entry `[entryStart, entryEnd]`.
///
/// The logged entry is never erased and never moved: [entryStart] is fixed, and
/// the entry is trimmed from its END only when the screen time does not fit in
/// the hour's empty space — and never below 1 minute. Screen time is placed in
/// the empty space, filling the TAIL gap first and then the HEAD gap, so the
/// result is 1 or 2 blocks that overlap neither the entry nor each other.
///
/// Guarantees: the entry keeps >= 1 minute; entry + blocks sum to <= 60 minutes;
/// no block overlaps the entry or another block; every block has `end > start`.
CarvePlan planCarve({
  required DateTime entryStart,
  required DateTime entryEnd,
  required DateTime hourStart,
  required int screenMinutes,
}) {
  final hourEnd = hourStart.add(const Duration(minutes: 60));

  // The caller (carveProposalsProvider) only emits proposals for an entry that
  // is fully contained in its hour; clamp defensively so a release build can't
  // produce negative gaps if that ever stops holding.
  assert(!entryStart.isBefore(hourStart), 'entry starts before its hour');
  assert(!entryEnd.isAfter(hourEnd), 'entry ends after its hour');

  final u = entryEnd.difference(entryStart).inMinutes;
  final head = entryStart.difference(hourStart).inMinutes.clamp(0, 60);
  final tail = hourEnd.difference(entryEnd).inMinutes.clamp(0, 60);
  final empty = head + tail;

  var s = screenMinutes.clamp(0, 60);

  // Trim only from the END, and only for what the empty space can't absorb.
  var trim = 0;
  if (s > empty) {
    final maxTrim = u > 1 ? u - 1 : 0; // never trim below 1 min of the entry
    trim = s - empty;
    if (trim > maxTrim) {
      trim = maxTrim;
      // Don't claim space we didn't free.
      s = empty + trim;
    }
  }

  final newEntryEnd = entryEnd.subtract(Duration(minutes: trim));

  final blocks = <ScreenBlock>[];
  var remaining = s;

  // Tail gap first: [newEntryEnd, hourEnd], filled from its start.
  final tailLen = hourEnd.difference(newEntryEnd).inMinutes; // == tail + trim
  final takeTail = remaining < tailLen ? remaining : tailLen;
  if (takeTail > 0) {
    blocks.add((newEntryEnd, newEntryEnd.add(Duration(minutes: takeTail))));
    remaining -= takeTail;
  }

  // Head gap next: [hourStart, entryStart], filled so it ends at entryStart.
  if (remaining > 0 && head > 0) {
    final takeHead = remaining < head ? remaining : head;
    blocks.add((entryStart.subtract(Duration(minutes: takeHead)), entryStart));
    remaining -= takeHead;
  }

  assert(
    _invariantsHold(
      entryStart: entryStart,
      newEntryEnd: newEntryEnd,
      hourStart: hourStart,
      hourEnd: hourEnd,
      originalEntryMinutes: u,
      blocks: blocks,
    ),
    'planCarve produced an invalid plan',
  );

  return (newEntryEnd: newEntryEnd, screenBlocks: blocks);
}

/// Debug-only check of the guarantees documented on [planCarve].
bool _invariantsHold({
  required DateTime entryStart,
  required DateTime newEntryEnd,
  required DateTime hourStart,
  required DateTime hourEnd,
  required int originalEntryMinutes,
  required List<ScreenBlock> blocks,
}) {
  final entryMinutes = newEntryEnd.difference(entryStart).inMinutes;

  // The entry keeps at least a minute (unless it never had one to begin with).
  if (originalEntryMinutes >= 1 && entryMinutes < 1) return false;
  if (entryMinutes > originalEntryMinutes) return false;

  var total = entryMinutes;
  for (var i = 0; i < blocks.length; i++) {
    final (start, end) = blocks[i];
    if (!end.isAfter(start)) return false;
    if (start.isBefore(hourStart) || end.isAfter(hourEnd)) return false;
    // No overlap with the (possibly trimmed) entry.
    if (start.isBefore(newEntryEnd) && end.isAfter(entryStart)) return false;
    // No overlap with any other block.
    for (var j = i + 1; j < blocks.length; j++) {
      final (otherStart, otherEnd) = blocks[j];
      if (start.isBefore(otherEnd) && end.isAfter(otherStart)) return false;
    }
    total += end.difference(start).inMinutes;
  }

  return total <= 60;
}
