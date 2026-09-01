# ChronoPlan — Past-day logging: read-only diagnostic

STEP 0. Read-only. No source file was modified. All quotes are verbatim from the
working tree at scan time (branch `main`, HEAD `b84e8f6`).

---

## 1. Day View past-day navigation

**File:** `lib/features/day_view/day_view_screen.dart`

### `_isToday` (lines 55–60)

```dart
  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }
```

### `_prevDay` (lines 62–63)

```dart
  void _prevDay() =>
      setState(() => _date = _date.subtract(const Duration(days: 1)));
```

### `_nextDay` (lines 65–70)

```dart
  void _nextDay() {
    final candidate = _date.add(const Duration(days: 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!candidate.isAfter(today)) setState(() => _date = candidate);
  }
```

### Date-nav wiring (lines 109–114) and the `_DateNav` widget (lines 233–280)

```dart
        title: _DateNav(
          date: _date,
          onPrev: _prevDay,
          onNext: _nextDay,
          canGoNext: !_isToday,
        ),
```

```dart
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          onPressed: onPrev,
          padding: EdgeInsets.zero,
        ),
        ...
        IconButton(
          icon: Icon(
            Icons.chevron_right_rounded,
            color: canGoNext ? Colors.white : Colors.white30,
          ),
          onPressed: canGoNext ? onNext : null,
          padding: EdgeInsets.zero,
        ),
```

**Can the user navigate to a PAST day?** **Yes, without limit.** `_prevDay`
(line 62) has **no guard at all** — no lower bound, no clamp — and the left
chevron's `onPressed: onPrev` (line 258) is never null. Only the FORWARD
direction is bounded: `_nextDay` refuses `candidate.isAfter(today)` (line 69),
and `canGoNext: !_isToday` (line 113) greys/disables the right chevron on today.

Day View is also reachable at an arbitrary past date from History —
`lib/features/history/history_screen.dart:113`:
`context.push('/day-view', extra: date)` → `lib/router.dart:30`:
`initialDate: state.extra as DateTime?` → `day_view_screen.dart:42`:
`_date = widget.initialDate ?? DateTime(now.year, now.month, now.day);`

**Is the "+" / empty-hour / log affordance shown on a past day?**
It is **shown on NO day — not even today.** Day View hardcodes the empty-hour tap
handler to `null` (lines 205–206):

```dart
                swipeEnabled: isToday,
                onEmptyHourTap: null,
```

There is **no condition such as `if (_isToday)` gating a log affordance, because
Day View has no log affordance to gate** — no FAB, no "+" button, no empty-hour
tap. The shared timeline treats a null handler as "no tappable empty hour" —
`lib/core/theme/hour_timeline.dart:156–164`:

```dart
                    // An empty hour is only tappable when a caller opts in; Day
                    // View passes null, so this element is absent there.
                    if (onEmptyHourTap != null && segments.isEmpty)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onEmptyHourTap!(hour),
                        ),
                      ),
```

For contrast, Routine View does opt in —
`lib/features/routine/routine_screen.dart:190`:
`onEmptyHourTap: (h) => _openSheet(startHour: h),`

Two things ARE day-gated in Day View:

- `swipeEnabled: isToday` (line 205) → swipe-to-delete is off on past days
  (`hour_timeline.dart:215–216`:
  `direction: swipeEnabled ? DismissDirection.endToStart : DismissDirection.none,`).
- The now-line, correctly (line 215):
  `if (!(isToday && now.hour == hour)) return const <Widget>[];`

Tapping an **existing** segment opens the sheet on any day (lines 188–198), so
*editing* a past entry is reachable; *creating* one on a past day is not.

---

## 2. How the log sheet gets its day + default times

**File:** `lib/features/log_entry/log_entry_sheet.dart`

### The sheet receives NO day — constructor (lines 44–47)

```dart
class LogEntrySheet extends ConsumerStatefulWidget {
  final LogEntry? existing;

  const LogEntrySheet({super.key, this.existing});
```

There is **no `day` / `date` / `selectedDay` parameter, and no provider read of a
selected day.** `selectedDateProvider` exists at
`lib/providers/log_entries_provider.dart:7` but the sheet never watches or reads
it. The sheet's only provider reads are `categoriesProvider`,
`logEntriesForDayProvider` (for **today**), `appDatabaseProvider`,
`aiServiceProvider`, and settings.

All three creation call-sites pass no day:

- `lib/features/shell/app_shell.dart:77` — the global nav-bar "+":
  `builder: (_) => const LogEntrySheet(),`
- `lib/features/dashboard/dashboard_screen.dart:160` —
  `builder: (_) => const LogEntrySheet(),`
- `lib/features/day_view/day_view_screen.dart:196` — **edit only**:
  `builder: (_) => LogEntrySheet(existing: entry),`

### `initState` (lines 66–80)

```dart
  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _descCtrl.text = e.description;
      _startTime = e.startTime;
      _endTime = e.endTime;
      _selectedCategoryId = e.categoryId;
    } else {
      _startTime = _defaultStart();
      _endTime = _startTime.add(const Duration(hours: 1));
    }
    _descCtrl.addListener(_onDescriptionChanged);
  }
```

### `_defaultStart` (lines 82–91)

```dart
  /// Defaults to the last completed hour — e.g. at 6:45 PM → 5:00 PM–6:00 PM.
  DateTime _defaultStart() {
    final now = DateTime.now();
    if (now.hour > 0) {
      return DateTime(now.year, now.month, now.day, now.hour - 1);
    }
    // Midnight edge case: yesterday 23:00
    final yesterday = now.subtract(const Duration(days: 1));
    return DateTime(yesterday.year, yesterday.month, yesterday.day, 23);
  }
```

**Verdict:** for a NEW entry the sheet defaults to **`DateTime.now()`'s date —
today** (the only exception is the 00:xx midnight case, which yields *yesterday*
23:00). It never defaults to a selected day, because no selected day is passed
in. For an EDIT (`widget.existing != null`) the date comes correctly from the
row's own `e.startTime` (line 72), which is why editing a past entry works.

### `_computeMissedHours` — actual name `computeMissedHours` (lines 26–42, top-level)

```dart
List<int> computeMissedHours(List<LogEntry> entries, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final missed = <int>[];
  for (int h = 0; h < reference.hour; h++) {
    final slotStart = today.add(Duration(hours: h));
    final slotEnd = slotStart.add(const Duration(hours: 1));
    final covered = entries.any(
      (e) =>
          !e.isUsageDerived &&
          e.startTime.isBefore(slotEnd) &&
          e.endTime.isAfter(slotStart),
    );
    if (!covered) missed.add(h);
  }
  return missed;
}
```

The function is day-agnostic *in principle* (`now` is injectable), but its **only
production caller hardcodes today** — `build`, lines 103–110:

```dart
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayEntries =
        ref.watch(logEntriesForDayProvider(today)).valueOrNull ?? [];
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    final missedHours =
        widget.existing == null ? computeMissedHours(todayEntries) : <int>[];
```

`now` is omitted → defaults to `DateTime.now()`; entries come from
`logEntriesForDayProvider(today)`. The strip's tap handler likewise rebuilds the
time on **today** (lines 147–153):

```dart
                    onTap: (h) {
                      setState(() {
                        _startTime = today.add(Duration(hours: h));
                        final end = _startTime.add(const Duration(hours: 1));
                        _endTime = end.isAfter(now) ? now : end;
                      });
                    },
```

Note also the loop bound `h < reference.hour` (line 30): on a past day every hour
0–23 should be a candidate, but this caps candidates at today's current hour.

---

## 3. The guards that can block a save

### "Cannot log future time." — `_pickTime`, lines 331–346

```dart
  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked == null || !mounted) return;

    final now = DateTime.now();
    final updated = DateTime(
        base.year, base.month, base.day, picked.hour, picked.minute);

    if (updated.isAfter(now)) {
      _showSnack('Cannot log future time.');
      return;
    }
```

**Comparison:** `updated` — the picked *time-of-day* re-attached to **`base`'s own
year/month/day** — vs. the real `DateTime.now()`. The reference is real "now",
which is **correct**. But note lines 333 and 340–341: the picker is
`showTimePicker`, and `updated` inherits `base.year, base.month, base.day`.
**There is no date picker anywhere in this sheet** — `showDatePicker` /
`CalendarDatePicker` do not appear in the file — so the user physically cannot
move an entry to a different calendar date from here.

### "End must be after start." — `_pickTime`, lines 348–351

```dart
    if (!isStart && !updated.isAfter(_startTime)) {
      _showSnack('End must be after start.');
      return;
    }
```

**Comparison:** picked end vs. `_startTime` — two same-day values, no reference to
today. **Correct as-is.**

Also inside `_pickTime`, lines 353–363 clamp the auto-extended end to now:

```dart
    setState(() {
      if (isStart) {
        _startTime = updated;
        if (!_endTime.isAfter(_startTime)) {
          final end = _startTime.add(const Duration(hours: 1));
          _endTime = end.isAfter(now) ? now : end;
        }
      } else {
        _endTime = updated;
      }
    });
```

Harmless on a past day — a past `_startTime + 1h` is never after now — but also
unnecessary there.

### "End time must be after start time." — `_save`, lines 366–370

```dart
  Future<void> _save() async {
    if (!_endTime.isAfter(_startTime)) {
      _showSnack('End time must be after start time.');
      return;
    }
```

**Comparison:** `_endTime` vs. `_startTime` only. **Correct as-is.** Note there is
**no future check in `_save` at all** — the only future guard in the whole file is
line 343 in `_pickTime`.

### Would these guards wrongly block a valid PAST entry?

**No.** Walking the actual logic:

- If `_startTime`/`_endTime` genuinely carried a past date (say 2026-08-30
  14:00→15:00): `updated.isAfter(now)` is **false** → passes;
  `updated.isAfter(_startTime)` compares two past same-day values → passes;
  `_endTime.isAfter(_startTime)` → passes. Save proceeds.
- That is exactly the observed behaviour when **editing** an existing past entry
  from Day View (`day_view_screen.dart:196` → `log_entry_sheet.dart:72–73` seeds
  from the row's real past timestamps). That path works today.
- The failure mode is the reverse of "the guard trips". For a NEW entry the times
  are seeded to **today** by `_defaultStart()` (lines 84–86), the time picker
  preserves `base`'s date (line 341), and nothing ever rewrites the date to the
  viewed day. So the guards **pass** and the row saves — **onto today**, silently.
  The user never sees "Cannot log future time." while trying to log a past day;
  they either see the entry land on the wrong date, or (more commonly) never find
  a way to open a create-sheet from a past day at all, because Day View exposes
  none.

---

## 4. The write path

**File:** `lib/core/database/daos/log_entries_dao.dart`

### `insertRetroactive` (lines 109–154) — the path the sheet uses

```dart
  Future<({List<int> ids, int requestedMinutes, int writtenMinutes})>
      insertRetroactive({
    required DateTime startTime,
    required DateTime endTime,
    required int? categoryId,
    required String description,
    bool isUsageDerived = false,
    bool avoidUsageDerived = false,
  }) async {
    final requestedMinutes = endTime.difference(startTime).inMinutes;

    final blockers = await _blockers(
      startTime,
      endTime,
      avoidUsageDerived: avoidUsageDerived,
    );
    final gaps = _gaps(startTime, endTime, blockers);
    if (gaps.isEmpty) {
      return (
        ids: const <int>[],
        requestedMinutes: requestedMinutes,
        writtenMinutes: 0,
      );
    }

    final ids = <int>[];
    var writtenMinutes = 0;
    for (final (gapStart, gapEnd) in gaps) {
      final id = await into(logEntries).insert(LogEntriesCompanion.insert(
        startTime: gapStart,
        endTime: gapEnd,
        categoryId: Value(categoryId),
        description: Value(description),
        isRealTime: const Value(false),
        isUsageDerived: Value(isUsageDerived),
        syncId: Value(_uuid.v4()),
      ));
      ids.add(id);
      writtenMinutes += gapEnd.difference(gapStart).inMinutes;
    }
```

### `insertRealTime` (lines 77–91) — **not used by the sheet**

```dart
  /// Real-time entry — inserted directly, never split or blocked.
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

The sheet's create path calls only `insertRetroactive` —
`log_entry_sheet.dart:384–393`:

```dart
        // avoidUsageDerived: the log fills only the empty space, slotting
        // around any confirmed screen time rather than stacking on it.
        final result = await db.logEntriesDao.insertRetroactive(
          startTime: _startTime,
          endTime: _endTime,
          categoryId: _selectedCategoryId,
          description: _descCtrl.text.trim(),
          avoidUsageDerived: true,
        );
```

(The AI parse sheet is the only other caller in this file, at
`log_entry_sheet.dart:624`, passing `e.startTime` / `e.endTime` derived from
`anchorTime: _startTime` — line 488 — so it inherits the same date as the sheet.)

**What day does the inserted row actually get?** Exactly the day carried by the
passed `startTime` / `endTime`. The DAO does **no** date normalization, no
clamping to today, and calls `DateTime.now()` nowhere in the insert path. It is
fully day-agnostic and would happily write a row dated last week.

**Is there an `isRealTime` / `isRetroactive` flag that depends on it being today?**
**No.** `insertRetroactive` hardcodes `isRealTime: const Value(false)` (line 142)
— a constant, not a date comparison. `insertRealTime` hardcodes `true` (line 89).
Neither consults the clock. `_blockers` (lines 174–190) filters on `isRealTime` /
`isUsageDerived` and range overlap only — again no "today" term.

**Would an entry saved while viewing a past day land on the correct past date?**
It lands on **whatever date the sheet handed it** — and since the sheet is never
told which day is being viewed (§2), a newly created entry lands **silently on
today**, not on the viewed past day. The DAO is not at fault; it is a faithful
passthrough.

---

## 5. Reactivity / display

**Day View entry list — driven by the selected day. Correct.**
`lib/features/day_view/day_view_screen.dart:91`:

```dart
    final entriesAsync = ref.watch(dayViewEntriesProvider(_date));
```

`lib/providers/log_entries_provider.dart:23–29`:

```dart
final dayViewEntriesProvider =
    StreamProvider.family<List<LogEntry>, DateTime>((ref, date) {
  return ref
      .watch(appDatabaseProvider)
      .logEntriesDao
      .watchEntriesOverlappingDay(date);
});
```

backed by a live drift `.watch()` keyed on that date —
`log_entries_dao.dart:35–44`:

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

So a correctly-dated past entry **would** appear on that day with no manual
refresh. The rest of the render pipeline is likewise keyed on `_date`:
`planHourRows(..., day: _date)` (line 140) and the routine overlay `day: _date`
(line 169).

**Missed-hours strip — NOT driven by the selected day.** The strip lives inside
the sheet, not Day View, and is keyed to today: `logEntriesForDayProvider(today)`
(`log_entry_sheet.dart:104–106`) feeding `computeMissedHours(todayEntries)` (line
110), where `today` is `DateTime.now()`'s date. It is also suppressed entirely on
edit (`widget.existing == null ? ... : <int>[]`, line 110). **There is no
missed-hours strip in Day View itself** — `computeMissedHours` and
`_MissedHoursStrip` have call-sites only in `log_entry_sheet.dart`.

---

## 6. Verdict

The blocker is **not** a single flipped boolean. It is that **`LogEntrySheet` has
no concept of "the day being viewed", and Day View exposes no way to create an
entry at all.** Two lines carry it, one in each file:

**(b) The log affordance is absent from Day View — on every day, not just past ones.**
`lib/features/day_view/day_view_screen.dart:206` — `onEmptyHourTap: null,` —
hardcoded null, so `hour_timeline.dart:158`
(`if (onEmptyHourTap != null && segments.isEmpty)`) never builds the tap target.
Day View has no FAB and no "+" either. The only create entry points are the global
nav "+" (`app_shell.dart:77`) and the dashboard (`dashboard_screen.dart:160`),
both `const LogEntrySheet()` with no day.

**(c, variant) The sheet defaults its times to today and can never be moved off today.**
`log_entry_sheet.dart:47` (`const LogEntrySheet({super.key, this.existing});` — no
day param); `:84–86` (`_defaultStart()` → `DateTime(now.year, now.month, now.day,
now.hour - 1)`); `:104–106`, `:110`, `:149` (missed-hours strip built on `today`);
and `:340–341` (`showTimePicker` + `DateTime(base.year, base.month, base.day,
picked.hour, picked.minute)` — time-of-day only; **no `showDatePicker` exists in
the file**).

Ruling out the others:

- **(a) is NOT the cause.** Past-day nav is fully open — `_prevDay`
  (`day_view_screen.dart:62`) is unguarded; only forward is bounded (lines 69 and
  113).
- **(d) is NOT the cause.** The future guard's reference is already correct:
  `log_entry_sheet.dart:343` compares `updated.isAfter(DateTime.now())` — real
  now, not end-of-selected-day and not today's date.
- **(e) IS a real secondary consequence.** Because the sheet only ever holds
  today's date, a save from anywhere lands on today. The DAO
  (`log_entries_dao.dart:109–154`) is innocent: it writes the passed timestamps
  verbatim, with `isRealTime: const Value(false)` as a constant and no clock
  reference.
- Editing an existing past entry already works end-to-end
  (`day_view_screen.dart:196` → `log_entry_sheet.dart:72–73` → all three guards
  pass). Only **creating** on a past day is impossible.
- Minor, adjacent: `swipeEnabled: isToday` (`day_view_screen.dart:205`) blocks
  swipe-delete on past days, and `computeMissedHours` caps candidate hours at
  `reference.hour` (`log_entry_sheet.dart:30`), which would under-report on a past
  day.

### The three guard messages, judged individually

| Message | Location | Comparison | Verdict |
|---|---|---|---|
| `Cannot log future time.` | `log_entry_sheet.dart:343–346` | `updated.isAfter(DateTime.now())` — real now | **Correct as-is.** The reference needs no change. What needs changing is that `updated` inherits its DATE from `base` (line 341), with no way to set that date to a past day. |
| `End must be after start.` | `log_entry_sheet.dart:348–351` | `!updated.isAfter(_startTime)` — no date reference | **Correct as-is.** Day-agnostic. |
| `End time must be after start time.` | `log_entry_sheet.dart:367–370` | `!_endTime.isAfter(_startTime)` — no date reference | **Correct as-is.** Day-agnostic. Note `_save` has **no** future check at all, so once the sheet can hold an arbitrary date, a future-vs-`now` guard will need to be added here too, not only in `_pickTime`. |
