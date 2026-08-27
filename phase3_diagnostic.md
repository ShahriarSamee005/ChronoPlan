# ChronoPlan Phase 3 PRE-CHECK DIAGNOSTIC

**Date:** 2026-08-27  
**Status:** Read-only diagnostic complete  
**Target:** Day View routine overlay rebuild

---

## A. Phase 2 Survivors

**Search for: `_ghostBlock`, `_slotCoverage`, `_hasCategoryMatch`, `todaySlots`, `allRoutineSlotsProvider`**

| Symbol | Status | Location | Notes |
|--------|--------|----------|-------|
| `_ghostBlock` | **DELETED** | — | Was in Version 1 commit `6d96084`, removed by Phase 2 |
| `_slotCoverage` | **DELETED** | — | Was in Version 1, removed by Phase 2 |
| `_hasCategoryMatch` | **DELETED** | — | Was in Version 1, removed by Phase 2 |
| `todaySlots` | **NOT FOUND** | — | Never existed in tracked history |
| `allRoutineSlotsProvider` | **EXISTS** | `lib/providers/routine_provider.dart:6` | Defined but not imported in day_view_screen.dart |

### Provider Definition
```dart
// lib/providers/routine_provider.dart
final allRoutineSlotsProvider = StreamProvider<List<RoutineSlot>>((ref) {
  return ref.watch(appDatabaseProvider).routineSlotsDao.watchAll();
});
```

---

## B. The Current _HourRow Structure

**File:** `lib/features/day_view/day_view_screen.dart:291–516`

### Current Stack Architecture (lines 342–358)
```dart
return Stack(
  clipBehavior: Clip.none,
  children: [
    // Hour divider, painted inside the Stack so it costs no
    // layout height (the scroll offset math depends on that).
    Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 0.5,
        color: Colors.white.withValues(alpha: 0.10),
      ),
    ),
    for (final seg in segments) ..._segment(seg, w),  // ← Entry segments here
    if (isCurrentHour) ..._nowLine(constraints.maxHeight),
  ],
);
```

### LayoutBuilder Context
```dart
Expanded(
  child: SizedBox(
    height: height,  // height = _rowHeight(rows, h) = _laneHeight * laneCount
    child: LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        return Stack( ... )  // Positioned children use w for horizontal layout
      },
    ),
  ),
)
```

### Critical Layout Facts
- **Coordinate System:** `top` = pixels from hour start; `left/right` = pixels from row edge; `width` = fraction of hour width
- **Segment Positioning:** `Positioned(left: left, top: seg.lane * _laneHeight, width: width, height: _laneHeight - 4)`
- **Now-line:** Painted last, rides above segments (drawn after `for (final seg in segments)...`)
- **Hour Divider:** Positioned at `top: 0`, cost-free (no layout height)

### _segment() Widget Structure (lines 369–478)
- Takes `HourSegment seg` and width `w`
- Returns list of Positioned widgets (usually 1, the Dismissible card)
- Segment top = `seg.lane * _laneHeight`, height = `_laneHeight - 4`
- Color derived from category via `byCatId[entry.categoryId]?.colorValue`

---

## C. RoutineSlot Model (Table Definition)

**File:** `lib/core/database/tables/routine_slots_table.dart:1–19`

```dart
class RoutineSlots extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().nullable()();
  TextColumn get label => text().withDefault(const Constant(''))();
  // 1=Mon … 7=Sun; 0=applies every day
  IntColumn get dayOfWeek => integer()();
  IntColumn get startHour => integer()(); // 0–23
  // User drags bottom edge to extend; stored as whole hours
  IntColumn get durationHours => integer().withDefault(const Constant(1))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  TextColumn get userId => text().nullable()();
  TextColumn get syncId => text().nullable()();
}
```

### Day Keying
- **`dayOfWeek`**: `1=Mon … 7=Sun`; `0=applies every day`
- No date-based keying; slots are weekly recurring only

### Query Filter in RoutineSlotsDao
**File:** `lib/core/database/daos/routine_slots_dao.dart:15–21`

```dart
Stream<List<RoutineSlot>> watchForDay(int dayOfWeek) =>
  (select(routineSlots)
        ..where((s) =>
            s.isActive.equals(true) &
            (s.dayOfWeek.equals(dayOfWeek) | s.dayOfWeek.equals(0)))
        ..orderBy([(s) => OrderingTerm(expression: s.startHour)]))
      .watch();
```

**Day View must use the same predicate:**
- Include only `isActive == true`
- Include only slots where `dayOfWeek == date.weekday OR dayOfWeek == 0`
- Note: Dart `DateTime.weekday` is `1=Mon … 7=Sun`, matching the slot `dayOfWeek` directly

---

## D. Old Verdict/Coverage Logic (Version 1 Commit `6d96084`)

**Extracted from git history.** All these functions were deleted by Phase 2; Phase 3 rebuilds them.

### Coverage Computation (lines in Version 1)
```dart
double _slotCoverage(RoutineSlot slot) {
  final slotStart = slot.startHour * 60;
  final slotEnd = (slot.startHour + slot.durationHours) * 60;
  final slotLen = slotEnd - slotStart;
  if (slotLen <= 0) return 0;
  int covered = 0;
  for (final e in entries) {
    final eStart = e.startTime.hour * 60 + e.startTime.minute;
    final eEnd = e.endTime.hour * 60 + e.endTime.minute;
    final overlap =
        (eEnd.clamp(slotStart, slotEnd) - eStart.clamp(slotStart, slotEnd))
            .clamp(0, slotLen);
    covered += overlap;
  }
  return covered / slotLen;
}
```

**How it works:**
- Computes total minute-of-day range for the slot: `[startHour*60, (startHour+durationHours)*60)`
- For each entry, computes overlap with slot in minutes (clamped to slot boundaries)
- Sums all overlaps
- Returns `sum / slotLen` — can exceed 1.0 if entries overlap each other within the slot
- **Does NOT filter by `isUsageDerived`** — counts all entries equally

### Category Match Test
```dart
bool _hasCategoryMatch(RoutineSlot slot) {
  final slotStart = slot.startHour * 60;
  final slotEnd = (slot.startHour + slot.durationHours) * 60;
  return entries.any((e) {
    final eStart = e.startTime.hour * 60 + e.startTime.minute;
    final eEnd = e.endTime.hour * 60 + e.endTime.minute;
    return e.categoryId == slot.categoryId &&
        eStart < slotEnd &&
        eEnd > slotStart;
  });
}
```

**Match rule:** True if ANY entry has the slot's `categoryId` AND its time range overlaps the slot.

### Verdict Decision & Colors
```dart
Color leftEdge;
double edgeWidth;
if (isPast) {  // isPast = slotEnd <= nowMinute
  final cov = _slotCoverage(slot);
  final match = _hasCategoryMatch(slot);
  if (cov >= 0.75 && match) {
    leftEdge = Colors.greenAccent;
    edgeWidth = 3.5;
  } else if (cov >= 0.10) {
    leftEdge = Colors.amberAccent;
    edgeWidth = 3.5;
  } else {
    leftEdge = Colors.redAccent.withValues(alpha: 0.7);
    edgeWidth = 3.5;
  }
} else {
  leftEdge = color.withValues(alpha: 0.22);  // slot's category color, thin
  edgeWidth = 1.5;
}
```

### Thresholds Summary
| State | Condition | Edge Color | Width | Semantic |
|-------|-----------|-----------|-------|----------|
| **Future** | `slotEnd > nowMinute` | Category color (low alpha) | 1.5px | Slot hasn't happened yet; neutral preview |
| **Past, Green** | `cov ≥ 0.75 AND match` | `Colors.greenAccent` | 3.5px | Slot well-covered by matching category |
| **Past, Amber** | `0.10 ≤ cov < 0.75` | `Colors.amberAccent` | 3.5px | Partial coverage, even without match |
| **Past, Red** | `cov < 0.10` | `Colors.redAccent` (0.7 alpha) | 3.5px | Slot mostly missed |

### Verdict Computation Scope
- Computed **once per slot**, not per hour
- Verdict is painted as the **left edge** of the ghost block
- Ghost block spans the entire slot duration (potentially multiple hours)
- Edge width is the visual verdict indicator, not the block itself

---

## E. LIVE Badge Location

**File:** `lib/features/day_view/day_view_screen.dart:451–469`

```dart
if (entry.isRealTime)
  Container(
    margin: const EdgeInsets.only(top: 2),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      'LIVE',
      style: TextStyle(
        color: color,
        fontSize: 8,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  ),
```

**Isolation:** Rendered only in the `seg.isFirstOfEntry ? Column(...)` branch, so removing it is a single block deletion. No provider or state change needed.

### insertRealTime Status
**File:** `lib/core/database/daos/log_entries_dao.dart:78–91`

```dart
Future<int> insertRealTime({
  required DateTime startTime,
  required DateTime endTime,
  required int? categoryId,
  required String description,
}) =>
    into(logEntries).insert(LogEntriesCompanion.insert(
      startTime: startTime,
      endTime: endTime,
      categoryId: Value(categoryId),
      description: Value(description),
      isRealTime: const Value(true),
      syncId: Value(_uuid.v4()),
    ));
```

**Call Sites:** Grep of entire `lib/` found **0 call sites**. This is dead code. Removing the LIVE badge will not break anything.

---

## F. Entries Available to Overlay

**File:** `lib/providers/log_entries_provider.dart:23–29`

```dart
final dayViewEntriesProvider =
    StreamProvider.family<List<LogEntry>, DateTime>((ref, date) {
  return ref
      .watch(appDatabaseProvider)
      .logEntriesDao
      .watchEntriesOverlappingDay(date);
});
```

**Query:** `watchEntriesOverlappingDay(date)` (lines 35–44 of log_entries_dao.dart)
```dart
Stream<List<LogEntry>> watchEntriesOverlappingDay(DateTime date) {
  final start = _dayStart(date);
  final end = start.add(const Duration(days: 1));
  return (select(logEntries)
        ..where((e) =>
            e.startTime.isSmallerThanValue(end) &
            e.endTime.isBiggerThanValue(start))
        ..orderBy([(e) => OrderingTerm(expression: e.startTime)]))
      .watch();
}
```

### Coverage Math Input
- **Same entries used for segments and coverage** — no separate feed
- Includes cross-midnight entries (e.g., last night's sleep shows on both days)
- No filter on `isUsageDerived` — all entries count equally (matching old behavior)

### LogEntry Fields (relevant to coverage)
```dart
class LogEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  BoolColumn get isRealTime => boolean().withDefault(const Constant(false))();
  BoolColumn get isUsageDerived => boolean().withDefault(const Constant(false))();
  // ... other fields (description, isAiParsed, createdAt, userId, syncId)
}
```

---

## G. Mismatches / Concerns

### 1. Multi-Hour Slot Painting Across Rows
- **Issue:** Routine slots span multiple hours, but `_HourRow` is a per-hour widget.
- **Current Row Structure:** Each hour gets its own Stack with its own LayoutBuilder and positioning context.
- **Required Solution:** Routine slots cannot be painted inside `_segment()` (which is per-entry per-hour). They must be painted at the **`_Timeline` level** or injected into each affected hour's Stack independently.
- **Design decision needed:** Should the overlay be:
  - (A) Rendered at `_Timeline` using absolute positioning spanning multiple hours? (Complex; needs to know all row heights)
  - (B) Computed in `_Timeline`, filtered per hour, then injected into each `_HourRow`'s Stack as a separate parameter? (Simpler; keeps row isolation)

### 2. Stack Children Ordering
- **Current order:** Divider → Segments → Now-line
- **Phase 3 overlay order:** Ghost block must be **before** segments so it renders behind them
- **Implementation:** Inject ghost-block Positioned widgets *before* the `for (final seg in segments)...` loop

### 3. Verdicts Per Row vs. Per Slot
- **Old design:** Verdict (edge color) was computed once per slot, applied to the whole ghost block.
- **New row-based design:** The verdict stays the same across all rows the slot covers (one slot → one color band).
- **Caveat:** If `_isToday` status differs between rows, or if different entries are filtered per row, the coverage would be recomputed. Ensure `_HourRow` receives the **full day's entries**, not a per-hour subset.

### 4. Day Calculation in Overlay Filter
- **RoutineSlot.dayOfWeek** is `1..7` matching `DateTime.weekday`.
- **Current Date:** Passed as `_date` to `_Timeline` → then to `_HourRow`.
- **Day-of-week extraction:** Use `_date.weekday.clamp(1, 7)` (already done in Routine screen).
- **Ensure:** If `_date` is not today, `.hour` and `.minute` for "now-line" logic and "isPast" check must still use `DateTime.now()` (which is already done).

### 5. isUsageDerived Filtering (Defer)
- **Old coverage included all entries.**
- **Current code:** Entries come from `dayViewEntriesProvider` unfiltered.
- **Phase 3 assumption:** Do NOT filter by `isUsageDerived` in coverage computation (match old behavior).
- **Future work:** If usage-derived rows should be excluded, that's a Phase 4 change; Phase 3 just rebuilds Phase 1's logic.

---

## Summary

| Item | Status | Ready? |
|------|--------|--------|
| Routine slot model fields & day keying | ✅ Confirmed | YES |
| Coverage formula & thresholds | ✅ Recovered from git | YES |
| Category match rule | ✅ Confirmed | YES |
| Entry provider (same as segments) | ✅ Confirmed | YES |
| LIVE badge isolated | ✅ Confirmed | YES |
| insertRealTime dead code confirmed | ✅ Confirmed | YES |
| Row layout structure (Stack/Positioned) | ✅ Confirmed | YES |
| Multi-hour slot spanning approach | ⚠️ Architecture needed | DEFER |
| Per-day filtering of slots | ✅ Routine screen pattern | YES |

### Phase 3 Pre-requisites Met
- ✅ Coverage logic recovered and validated
- ✅ Routing slot queries confirmed (use `watchForDay(date.weekday)`)
- ✅ Color thresholds & edge widths documented
- ✅ Row layout architecture understood
- ✅ Entry provider identified (no filtering needed for Phase 3)

### Blockers / Design Decisions
- 🔴 **Multi-hour spanning:** Decide between injecting ghosts into each row (simpler) or painting at timeline level (more complex)
- 🔴 **Verdict computation timing:** Should verdicts be recomputed every minute (with now-line), or once per day load?
- 🟡 **LIVE badge removal timing:** Coordinate with any real-time feature deprecation; currently dead code

---

**Report Date:** 2026-08-27  
**Diagnostic Status:** Complete  
**Next Step:** Awaiting Phase 3 implementation plan with multi-hour spanning decision
