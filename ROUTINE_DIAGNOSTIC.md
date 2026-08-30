# ROUTINE_DIAGNOSTIC.md

Read-only diagnostic of the current Routine screen and its data/provider stack, to
ground a row-based redesign in real code. No app files were modified.

---

## 1. Routine slot data model

**Table file:** `lib/core/database/tables/routine_slots_table.dart`
**DAO file:** `lib/core/database/daos/routine_slots_dao.dart`

**Dart class:** `RoutineSlots` → generated SQL table name **`routine_slots`** (drift
snake-cases the class name). Row data class: `RoutineSlot`; companion:
`RoutineSlotsCompanion`.

**Every column** (`routine_slots_table.dart:3-19`):

| Column | Type (Drift) | Notes |
|---|---|---|
| `id` | `IntColumn` `integer().autoIncrement()` | PK |
| `categoryId` | `IntColumn` `integer().nullable()` | nullable; no explicit FK constraint in the table def |
| `label` | `TextColumn` `text().withDefault(const Constant(''))` | defaults to empty string |
| `dayOfWeek` | `IntColumn` `integer()` | **required, no default.** Comment: `1=Mon … 7=Sun; 0=applies every day` |
| `startHour` | `IntColumn` `integer()` | required. Comment: `0–23` |
| `durationHours` | `IntColumn` `integer().withDefault(const Constant(1))` | whole hours; comment: "User drags bottom edge to extend; stored as whole hours" |
| `isActive` | `BoolColumn` `boolean().withDefault(const Constant(true))` | |
| `createdAt` | `DateTimeColumn` `dateTime().clientDefault(() => DateTime.now())` | |
| `userId` | `TextColumn` `text().nullable()` | sync scaffolding |
| `syncId` | `TextColumn` `text().nullable()` | sync scaffolding |

**How TIME is stored:** as an **hour integer + whole-hour duration**, NOT a
DateTime, NOT minute-of-day, NOT a start+end pair. A slot = `startHour` (0–23) plus
`durationHours` (whole hours). There is **no end column** and **no minute
granularity** — everything is hour-aligned.

**`dayOfWeek` encoding:** `1–7 = Mon–Sun`, `0 = every day`. Confirmed by the table
comment (`routine_slots_table.dart:7`), the DAO's `watchForDay`
(`routine_slots_dao.dart:15-21`, which ORs `dayOfWeek == dayOfWeek` with
`dayOfWeek == 0`), and the screen filter (`routine_screen.dart:106-108`). This
matches the scheme the overlay planner assumes.

**Two slots for the same hour/day?** Yes — there is **no uniqueness constraint** of
any kind (only the autoincrement PK). Nothing at the DB level prevents overlapping
or duplicate slots on the same day/hour. Collisions are resolved only downstream:
`planRoutineEdges` documents "if two slots cover the same hour, the one with the
smaller `startHour` wins" (`routine_overlay_planner.dart:29-31, 69-73`); the Routine
screen itself just paints every slot block (later ones stack on top in Stack order).

**A 4-hour slot in the table:** **ONE row** with `startHour = X`, `durationHours = 4`.
Not four rows.

---

## 2. Routine DAO (`lib/core/database/daos/routine_slots_dao.dart`)

`@DriftAccessor(tables: [RoutineSlots])`, `class RoutineSlotsDao`.

| Method | Signature | Reactive? |
|---|---|---|
| `watchForDay` | `Stream<List<RoutineSlot>> watchForDay(int dayOfWeek)` | **Yes** — `.watch()`; filters `isActive == true AND (dayOfWeek == arg OR dayOfWeek == 0)`, ordered by `startHour` |
| `getForDay` | `Future<List<RoutineSlot>> getForDay(int dayOfWeek)` | No — one-shot `.get()`, same filter/order |
| `insertSlot` | `Future<int> insertSlot(RoutineSlotsCompanion entry)` | write |
| `updateSlot` | `Future<void> updateSlot(RoutineSlotsCompanion entry)` | write, `where id == entry.id.value` |
| `deleteSlot` | `Future<void> deleteSlot(int id)` | write |
| `setActive` | `Future<void> setActive(int id, {required bool active})` | write (isActive only) |
| `watchAll` | `Stream<List<RoutineSlot>> watchAll()` | **Yes** — `.watch()`, ordered by `dayOfWeek` then `startHour`, **no isActive filter** |
| `copyDaySlots` | `Future<void> copyDaySlots(int fromDay, List<int> toDays)` | write; see §4 |

**Reactive vs one-shot:** `watchForDay` and `watchAll` are reactive Drift `.watch()`
streams; `getForDay` is a one-shot. The Routine screen uses the reactive `watchAll`
(via `allRoutineSlotsProvider`), NOT `watchForDay`.

**Pure/testable helpers already extracted for routine logic:**
- `lib/features/day_view/routine_overlay_planner.dart` — `planRoutineEdges(...)`,
  pure, Flutter/Drift-free, unit-tested. But this computes **per-hour verdict/edge
  overlay** data for Day View, not slot *layout* for the Routine screen.
- **No** slot-layout / lane-packing helper specific to the Routine screen exists
  ("not found"). The Routine screen does its geometry inline in `_slotBlock`.

---

## 3. Provider chain feeding the Routine screen

`routine_screen.dart` reads three providers:

| Provider | File | Kind | Family? |
|---|---|---|---|
| `allRoutineSlotsProvider` | `lib/providers/routine_provider.dart:6-8` | **StreamProvider** `<List<RoutineSlot>>` over `routineSlotsDao.watchAll()` | **No** — streams ALL slots for all days; the screen filters by day **inline** |
| `categoriesProvider` | `lib/providers/categories_provider.dart:6-8` | **StreamProvider** `<List<Category>>` over `categoriesDao.watchAll()` | No |
| `appDatabaseProvider` | `lib/providers/database_provider.dart:8-12` | **plain `Provider<AppDatabase>`** (read-only, for direct DAO calls) | No |

Key point: the screen does **not** use a `.family` keyed by day. It watches the full
slot list once and filters `dayOfWeek == _selectedDay || dayOfWeek == 0` in
`build()` (`routine_screen.dart:105-109`). Switching days is pure local `setState`
re-filtering the already-streamed list — **no re-query** hits the DB on day change.

---

## 4. Current Routine screen UI (`lib/features/routine/routine_screen.dart`)

**Render approach around `_hourPx = 72.0`** (`routine_screen.dart:23`): a
**`SingleChildScrollView` → `SizedBox(height: hourPx*24 + 1)` → `Row`** of
[hour-label gutter | timeline body]. The timeline body is a **`Stack` of absolutely
`Positioned` children** (`routine_screen.dart:296-366`):
1. 24 tappable empty-cell `GestureDetector`s, one per hour, **only** where the hour
   is not covered by a slot (`covered` check at `:330-332`);
2. 24 hour-divider lines;
3. one `_slotBlock` per slot.

It is **NOT** a `ListView` and **NOT** per-hour cell widgets stacked vertically —
it's absolute positioning by pixel math (`top = startHour * hourPx`).

**How a multi-hour slot renders today:** **CORRECTION to the brief's assumption** —
a multi-hour slot renders as **ONE full-height block spanning all its hours**, not a
chip at the start hour. `_slotBlock` sets
`top = startHour*hourPx + 1`, `height = (durationHours*hourPx - 2)` clamped to ≥6
(`routine_screen.dart:370-371`). So a 4h slot is a single block 4×72 px tall. (The
"chip at start hour" behavior was the *Day-View overlay's* old look, not this
screen.)

**Day tabs** (`_DayPills`, `routine_screen.dart:95-99, 226-271`): selected day is
local state `int _selectedDay` (init `DateTime.now().weekday.clamp(1,7)`,
`:34`). Tabs are `ActionChip`s for Mon–Sun (`_days`, `:26-29`). Tapping calls
`onSelect → setState(() => _selectedDay = d)`. As noted in §3, this only re-filters
the in-memory stream; no DB re-query.

**CREATE flow:** tapping an uncovered hour cell → `onTapHour(h)` →
`_openSheet(startHour: h)` (`:115, 138-150`) → `showModalBottomSheet` of
`_SlotSheet` (root navigator, `:139-149`). There is **no "+" FAB** — creation is
tap-an-empty-hour only. Fields collected in `_SlotSheet`
(`:455-644`): **Label** (optional `TextField`), **Duration** (`FilterChip`s 1/2/3/4h,
`:536-544`), **Category** (single-select `FilterChip`s from non-archived categories,
tap-again to clear, `:549-577`). The **day** is fixed to the currently selected tab
(`dayOfWeek: _selectedDay` passed in, written at `:624`); the **start hour** comes
from the tapped cell. There is **no day-of-week picker and no "every day" (0)
option** in the sheet — every slot created here is bound to the one selected weekday.
The header shows the computed time range `HH:00 – HH:00` (`:518-523`).

**EDIT flow:** tapping an existing slot block → `GlassCard.onTap` →
`onTapSlot(slot)` (`:402, 116`) → `_openSheet(existing: slot)` → same `_SlotSheet`
prefilled from `existing` (label, categoryId, durationHours; `:464-472`). Save routes
to `updateSlot` when `existing != null` (`:630-633`). **Not editable in the sheet:**
`startHour` and `dayOfWeek` (they're passed through unchanged, so you cannot move a
slot to a different hour or day via edit — only label/duration/category).

**DELETE flow:** **swipe** — each slot block is wrapped in a `Dismissible`
(`key: ValueKey('rslot_${slot.id}')`, `direction: DismissDirection.endToStart`,
`routine_screen.dart:381-394`). `onDismissed → onDeleteSlot(slot.id) →
routineSlotsDao.deleteSlot(id)` (`:117-120, 394`). Confirmed the `Dismissible` is
still present and wired. There is **no** long-press and **no** delete button inside
the edit sheet. (Note: no confirm dialog and no undo — swipe deletes immediately.)

**COPY-TO-DAYS** (`copy_all_rounded` AppBar action → `_showCopyDialog`,
`:77-82, 152-221`): builds `sourceSlots = slots where dayOfWeek == _selectedDay`
(only that day's day-specific slots; every-day 0 slots are excluded). If empty →
SnackBar "No slots on this day to copy." Otherwise an `AlertDialog` with a
`CheckboxListTile` per *other* weekday (`:180-190`). On **Copy** →
`routineSlotsDao.copyDaySlots(_selectedDay, selected.toList())` (`:202-206`) then a
confirmation SnackBar. **What `copyDaySlots` writes** (`routine_slots_dao.dart:55-74`):
reads active slots where `dayOfWeek == fromDay`, and for each target day inserts a
**new row** copying `categoryId, label, startHour, durationHours, isActive=true` with
`dayOfWeek = targetDay`. It does **not** de-duplicate or clear existing target-day
slots — repeated copies **accumulate duplicate rows**.

**Anything else interactive:** back button (when `canPop`, `:63-69`); profile
button → `context.push('/profile')` (`:83-87`); the initial auto-scroll to
`6 * hourPx` (06:00) on first frame (`:35-41`). No now-line, no LIVE badge, no
long-press menu, no drag-to-resize (duration is chip-based despite the "drag" comment
in the table).

---

## 5. Reusability check vs the new Day View

**`lib/features/day_view/day_view_screen.dart` building blocks:**

| Widget / const | Kind | Importable? |
|---|---|---|
| `_HourRow` | `StatelessWidget`, one hour's Row(gutter + Stack of segments) | **Private** — leading underscore, not importable |
| `_Timeline` | `StatelessWidget`, the `ListView.builder` of 24 `_HourRow`s | **Private** |
| `_segment(HourSegment, double)` | method on `_HourRow` returning the `Dismissible`/`GlassCard` bar | **Private** method |
| `_routineEdge(...)` / `_verdictToEdge(...)` / `_nowLine(...)` | methods on `_HourRow` | **Private** |
| `_laneHeight = 52.0` | file-level const | **Private** (`_` prefix) |
| `_minSegWidth = 48.0` | file-level const | **Private** |
| `_gutterWidth = 52.0` | file-level const | **Private** |

→ **None of the Day-View row/segment widgets or sizing constants are reusable by
import.** They are all private to `day_view_screen.dart`. A redesign that wants the
same look must either duplicate the widget code or extract a shared widget first.

**`lib/features/day_view/hour_row_planner.dart` — `planHourRows`:**
- **Input:** `List<PlanEntry>` where `PlanEntry = ({int entryId, DateTime start,
  DateTime end})` (`hour_row_planner.dart:9`), plus required `DateTime day`.
- **Output:** `List<List<HourSegment>>` — exactly 24 lists (index = hour 0–23), each
  a lane-packed, overlap-resolved list of `HourSegment` records
  (`{entryId, startMin 0–59, endMin 1–60, isFirstOfEntry, isLastOfEntry, lane,
  laneCount}`, `:12-20`).
- **Can routine slots map into it as-is?** **Partially — a mapping shim is needed.**
  `planHourRows` is keyed entirely on **`DateTime start`/`end`**, which it converts to
  minutes-from-midnight (`:51-52`). Routine slots have **no DateTime and no minutes**
  — only `startHour` + `durationHours`. To reuse it, a caller must synthesize
  DateTimes for the displayed day, e.g. `start = DateTime(day, 0,0).add(startHour h)`,
  `end = start.add(durationHours h)`, and use `slot.id` as `entryId`. With that shim
  it would yield exactly the per-hour, **multi-hour-spanning, lane-packed** rows a
  row-based Routine redesign wants (including overlap→lanes, which the current
  absolute-Stack screen does NOT do — overlapping slots currently just paint on top of
  each other). So: **reusable for slots only through a thin hour→DateTime adapter;
  not directly, because it assumes DateTime start/end that hour-based slots lack.** No
  changes to `planHourRows` itself are required.

**`lib/features/day_view/routine_overlay_planner.dart` — applicable-slot filter:**
- The planner's own doc **assumes** slots are pre-filtered: *"Assumptions: slots are
  already filtered to isActive=true and applicable to [day]'s weekday"*
  (`routine_overlay_planner.dart:49-51`). It does **not** contain an extracted,
  importable filter function — **"not found"** as a reusable helper.
- The actual `isActive + dayOfWeek` filter is written **inline** in two places:
  - Day View: `s.isActive && (s.dayOfWeek == _date.weekday || s.dayOfWeek == 0)`
    (`day_view_screen.dart:157-160`).
  - Routine screen: `s.dayOfWeek == _selectedDay || s.dayOfWeek == 0` (**note: this
    one does NOT check `isActive`**, `routine_screen.dart:106-108`).
- **Reusability:** the *rule* (day-match OR every-day, plus isActive) is exactly what a
  per-day Routine display needs, but there is no shared function to call today — it
  would need extracting. The two inline copies also **differ** (Routine omits the
  `isActive` check), which is worth reconciling in the redesign.

---

## 6. Interaction parity checklist (redesign must preserve all of these)

- Select a weekday (Mon–Sun) via day pills; view updates to that day's slots.
- See every slot for the selected day **plus** every "every-day" (`dayOfWeek == 0`)
  slot, visually distinguished (every-day slots render fainter + "Every day" label).
- See slots positioned on a 24-hour timeline, each block spanning its full duration.
- Auto-scroll to ~06:00 on entry; free vertical scroll of the full 24h.
- Tap an **empty** hour to create a new slot starting at that hour.
- In the create/edit sheet: set an optional **label**, pick **duration** (1/2/3/4h),
  pick a single **category** (or none), see the live time-range header; **Save**.
- New slots are bound to the **currently selected weekday** (no every-day option in
  the sheet today).
- Tap an **existing** slot to edit its label / duration / category (start hour and
  weekday are not editable via the sheet).
- **Swipe** a slot (right-to-left) to delete it immediately (no confirm/undo).
- **Copy** all of the selected day's day-specific slots to one or more other
  weekdays (multi-select checklist dialog + confirmation SnackBar).
- AppBar: back (when applicable) and profile navigation.

*(Behaviors to consciously decide on, not silently drop: no isActive toggle in UI
today; overlapping slots stack visually rather than lane-split; copy accumulates
duplicates; delete has no confirm/undo.)*

---

## 7. Tests touching routine slots

- `test/routine_overlay_planner_test.dart` — unit tests for `planRoutineEdges`
  (verdict/overlay pure logic).
- `test/day_view_routine_overlay_test.dart` — widget tests for the Day-View routine
  **overlay edge** (added in Phase 3a): render-tree tests using `routineSlotsDao`
  inserts + the overlay planner.
- **No** `routine_screen` widget test and **no** `routine_slots_dao` unit test exist
  ("not found"). The `hour_row_planner` has its own test
  (`test/hour_row_planner_test.dart`) but it is not routine-slot-specific.

---

*End of diagnostic. No app/config/test files were modified; this report is the only
file created.*
