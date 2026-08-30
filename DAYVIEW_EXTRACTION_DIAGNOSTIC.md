# Day View extraction diagnostic (STEP 0b, READ-ONLY)

Maps the internals of the rebuilt Day View timeline so a SHARED per-hour-row
widget can be designed that both Day View and the Routine screen draw through.
Nothing was modified. Findings are exact — file paths + line numbers against the
current tree.

Primary file: [lib/features/day_view/day_view_screen.dart](lib/features/day_view/day_view_screen.dart)
Planner: [lib/features/day_view/hour_row_planner.dart](lib/features/day_view/hour_row_planner.dart)
Overlay planner: [lib/features/day_view/routine_overlay_planner.dart](lib/features/day_view/routine_overlay_planner.dart)

---

## 1. Timeline structure (day_view_screen.dart)

### Private widgets/classes that draw the timeline body

| Class | Role | File:line | Constructor params (name : type) |
|---|---|---|---|
| `_Timeline` | Outer list (the `ListView.builder`) | day_view_screen.dart:280 | `rows: List<List<HourSegment>>`, `byId: Map<int, LogEntry>`, `cats: List<Category>`, `routineEdges: List<HourRoutine?>?`, `isToday: bool`, `scrollCtrl: ScrollController`, `onEntryTap: void Function(LogEntry)`, `onDeleteEntry: void Function(LogEntry)` |
| `_HourRow` | Per-hour row widget (gutter + track) | day_view_screen.dart:328 | `hour: int`, `segments: List<HourSegment>`, `height: double`, `byId: Map<int, LogEntry>`, `byCatId: Map<int, Category>`, `routineEdge: HourRoutine?`, `isToday: bool`, `now: DateTime`, `onEntryTap: void Function(LogEntry)`, `onDeleteEntry: void Function(LogEntry)` |
| `_DateNav` | AppBar date navigator (NOT timeline body) | day_view_screen.dart:229 | `date: DateTime`, `onPrev: VoidCallback`, `onNext: VoidCallback`, `canGoNext: bool` |

There is **no dedicated segment widget class**. The segment is built by an
instance method on `_HourRow`: `List<Widget> _segment(HourSegment seg, double w)`
(day_view_screen.dart:476). Likewise the routine edge and now-line are `_HourRow`
methods, not classes:
- `Widget _routineEdge(HourRoutine routine, double height, int colorValue)` — day_view_screen.dart:415
- `(Color, double) _verdictToEdge(RoutineVerdict verdict, Color categoryColor)` — day_view_screen.dart:463
- `List<Widget> _nowLine(double h)` — day_view_screen.dart:571

Free-function helpers at file scope:
- `int _laneCountOf(List<List<HourSegment>> rows, int hour)` — day_view_screen.dart:221
- `double _rowHeight(List<List<HourSegment>> rows, int hour)` — day_view_screen.dart:224

### How the 24-row list is built

`_Timeline.build` (day_view_screen.dart:302) returns a `ListView.builder`:
```dart
return ListView.builder(
  controller: scrollCtrl,
  // Rows vary in height with their lane count, so no itemExtent.
  itemCount: 24,
  padding: const EdgeInsets.only(bottom: 100),
  itemBuilder: (_, h) => _HourRow(...),
);
```
- `itemCount: 24` (day_view_screen.dart:310) — one row per hour, always all 24.
- No `itemExtent` — rows vary in height.
- `padding: const EdgeInsets.only(bottom: 100)` (day_view_screen.dart:311).
- `byCatId` map is built once outside the builder (day_view_screen.dart:304).

### How each row's HEIGHT is computed (laneCount → height)

```dart
int _laneCountOf(List<List<HourSegment>> rows, int hour) =>
    rows[hour].isEmpty ? 1 : rows[hour].first.laneCount;      // :221

double _rowHeight(List<List<HourSegment>> rows, int hour) =>
    _laneHeight * _laneCountOf(rows, hour);                    // :224
```
So `rowHeight = _laneHeight * laneCount` (min laneCount = 1). The planner
guarantees a uniform `laneCount` across an hour's segments, so `first.laneCount`
is representative.

### Exact constants

| Constant | Value | File:line | Meaning |
|---|---|---|---|
| `_laneHeight` | `52.0` | day_view_screen.dart:21 | height of one lane inside an hour row |
| `_minSegWidth` | `48.0` | day_view_screen.dart:25 | floor width for tiny slivers (tap target) |
| `_gutterWidth` | `52.0` | day_view_screen.dart:27 | hour-label gutter width (left) |
| right gutter | `8.0` | day_view_screen.dart:410 | `const SizedBox(width: 8)` after the track |
| segment vertical inset | `4` | day_view_screen.dart:505 | `height: _laneHeight - 4` breathing room |
| corner radius | `8` | day_view_screen.dart:491 | `const r = Radius.circular(8)` |

### Structure of ONE row

`_HourRow.build` (day_view_screen.dart:354) returns a `Row` with
`crossAxisAlignment: CrossAxisAlignment.start` and three children:

1. **Hour-label gutter** — `SizedBox(width: _gutterWidth)` → `Padding(right:6, top:2)` → right-aligned `Text('HH:00')` in white38, 10px (day_view_screen.dart:360–374).
2. **Block track** — `Expanded` → `SizedBox(height: height)` → `LayoutBuilder` → `Stack(clipBehavior: Clip.none)` (day_view_screen.dart:375–408). `final w = constraints.maxWidth;`
3. **Right gutter** — `const SizedBox(width: 8)` (day_view_screen.dart:410).

The block track IS a `LayoutBuilder` → `Stack`. **Stack children in order**
(day_view_screen.dart:383–403):

| Order | Layer | Positioned? | File:line |
|---|---|---|---|
| 1 | Hour divider (0.5px white line at top:0) | `Positioned` (top/left/right) | :386 |
| 2 | Routine overlay edge, `if (routineEdge != null)` | `Positioned` (inside `_routineEdge`) | :396 |
| 3 | Segments — `for (final seg in segments) ..._segment(seg, w)` | each is a `Positioned` | :402 |
| 4 | Now-line — `if (isCurrentHour) ..._nowLine(constraints.maxHeight)` | two `Positioned` | :403 |

So paint order back→front: divider, routine edge, segments, now-line. All four
layers are `Positioned`.

---

## 2. Segment geometry (the math to share)

`_segment` (day_view_screen.dart:476). The positioning math (day_view_screen.dart:482–488):
```dart
var left = seg.startMin / 60 * w;
var width = (seg.endMin - seg.startMin) / 60 * w;
if (width < _minSegWidth) width = _minSegWidth;
if (width > w) width = w;
// A floored sliver near the right edge would overflow — shift it back in.
if (left + width > w) left = w - width;
if (left < 0) left = 0;
```
- `left` = fraction of the hour elapsed × track width.
- `width` = fraction of the hour spanned × track width, floored at `_minSegWidth`, capped at `w`.
- Overflow clamp: if `left + width > w`, shift `left` back to `w - width`; then floor `left` at 0.

The `Positioned` uses (day_view_screen.dart:500–505):
```dart
Positioned(
  left: left,
  top: seg.lane * _laneHeight,
  width: width,
  height: _laneHeight - 4,
```
- `top = seg.lane * _laneHeight`
- `height = _laneHeight - 4`

### Corner roundings

day_view_screen.dart:491–497:
```dart
const r = Radius.circular(8);
final radius = BorderRadius.only(
  topLeft: seg.isFirstOfEntry ? r : Radius.zero,
  bottomLeft: seg.isFirstOfEntry ? r : Radius.zero,
  topRight: seg.isLastOfEntry ? r : Radius.zero,
  bottomRight: seg.isLastOfEntry ? r : Radius.zero,
);
```
`isFirstOfEntry` rounds the LEFT corners; `isLastOfEntry` rounds the RIGHT
corners. A multi-hour entry thus reads as one continuous bar (only its outer ends
are rounded).

### Category color resolution

day_view_screen.dart:480:
```dart
final color = Color(byCatId[entry.categoryId]?.colorValue ?? 0xFF607D8B);
```
`entry.categoryId` → `byCatId` (`Map<int, Category>`) → `Category.colorValue`
(int) → `Color(...)`. Fallback `0xFF607D8B` (blue-grey) when the category is
missing/null. `byCatId` is built in `_Timeline.build` (day_view_screen.dart:304):
`final byCatId = {for (final c in cats) c.id: c};`

The routine edge resolves its color the same way, inline at the call site
(day_view_screen.dart:400): `byCatId[routineEdge!.categoryId]?.colorValue ?? 0xFF607D8B`.

---

## 3. Per-row background layers

### Now-line

`_nowLine(double h)` (day_view_screen.dart:571), where `h = constraints.maxHeight`.
Vertical position:
```dart
var y = now.minute / 60 * h;
if (y > h - 1.5) y = h - 1.5;
if (y < 0) y = 0;
```
- `y = now.minute/60 × rowHeight`, clamped so the 1.5px line stays inside the row.
- Constrained to the current row ONLY by the guard at the call site
  (day_view_screen.dart:403): `if (isCurrentHour) ..._nowLine(...)`, where
  `isCurrentHour = isToday && now.hour == hour` (day_view_screen.dart:355).
- Layering: drawn LAST in the Stack (front). Two `Positioned`: a 1.5px red
  `ColoredBox` line (key `Key('now_line')`, day_view_screen.dart:577) and a 7×7 red
  dot at `top: y - 2.75`. Both wrapped in `IgnorePointer` (day_view_screen.dart:582, :589).

### Routine overlay edge

Drawn by `_HourRow._routineEdge` (day_view_screen.dart:415), called at
day_view_screen.dart:396–400 (2nd in the Stack, BEHIND segments). Data it reads:
- `routineEdge` (`HourRoutine`) → `.verdict`, `.categoryId` (`.isPast` is carried but not used in the render).
- Category color via `byCatId[routineEdge!.categoryId]?.colorValue ?? 0xFF607D8B`.

Key lines (day_view_screen.dart:415–460):
```dart
final color = Color(colorValue);
final (edgeColor, edgeWidth) = _verdictToEdge(routine.verdict, color);
return Positioned(
  top: 0, left: 2, right: 2, height: height,
  child: IgnorePointer(
    child: Stack(fit: StackFit.expand, children: [
      Container( // rounded faint base block
        key: ValueKey('routine_edge_$hour'),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.14), width: 0.5),
        ),
      ),
      Positioned( // verdict accent bar on the left edge
        left: 0, top: 0, bottom: 0,
        child: Container(
          key: ValueKey('routine_accent_$hour'),
          width: edgeWidth,
          decoration: BoxDecoration(color: edgeColor, ...),
        ),
      ),
    ]),
  ),
);
```
Verdict → (color, width) mapping (`_verdictToEdge`, day_view_screen.dart:463–474):
green → `Colors.greenAccent, 3.5`; amber → `Colors.amberAccent, 3.5`;
red → `Colors.redAccent.withValues(alpha:0.7), 3.5`;
neutral → `categoryColor.withValues(alpha:0.22), 1.5`.
Whole edge wrapped in `IgnorePointer` so it never steals a segment tap.

### Classification of per-row layers

| Layer | Class |
|---|---|
| Hour-label gutter | GENERIC row scaffolding |
| Block track (`LayoutBuilder`→`Stack`) | GENERIC row scaffolding |
| Segment positioning (`_segment` geometry, corners, color) | GENERIC row scaffolding |
| Hour divider (0.5px line) | GENERIC row scaffolding |
| Right gutter (8px) | GENERIC row scaffolding |
| **Routine overlay edge** | **DAY-VIEW-SPECIFIC** (background layer) |
| **Now-line** | **DAY-VIEW-SPECIFIC** (background/foreground layer) |

The routine edge and now-line are the two variable layers a shared widget should
accept from the caller (as optional back/front layer builders) rather than
hard-code.

---

## 4. Interactions wired into a segment

### Tap → edit sheet

The `GlassCard`'s own `onTap` (day_view_screen.dart:528–529):
```dart
child: GlassCard(
  onTap: () => onEntryTap(entry),
```
Comment at day_view_screen.dart:526–527 notes GlassCard's detector is opaque and
innermost, so the tap must be registered there — an outer `GestureDetector` never
sees it. `onEntryTap` is supplied by `DayViewScreen.build` and opens
`LogEntrySheet` via `showModalBottomSheet` (day_view_screen.dart:191–197).

### Swipe-to-delete

`Dismissible` wrapping the card (day_view_screen.dart:506–521):
```dart
child: Dismissible(
  key: ValueKey('seg_${seg.entryId}_${hour}_${seg.lane}'),
  direction: isToday ? DismissDirection.endToStart : DismissDirection.none,
  resizeDuration: null,
  background: Container( ... redAccent 0.20 ... delete_outline icon ... ),
  onDismissed: (_) => onDeleteEntry(entry),
  child: ClipRRect( ... GlassCard ... ),
),
```
- direction: `isToday ? DismissDirection.endToStart : DismissDirection.none` (:508–509).
- key format: `ValueKey('seg_${seg.entryId}_${hour}_${seg.lane}')` (:507).
- `resizeDuration: null` (:510).
- `onDismissed: (_) => onDeleteEntry(entry)` (:521).

The `_pendingDeleteIds` guard lives in `_DayViewScreenState`, not the segment:
- Declared: `final Set<int> _pendingDeleteIds = {};` (day_view_screen.dart:40).
- `onDeleteEntry` adds to it and calls the DAO (day_view_screen.dart:198–206):
  ```dart
  setState(() => _pendingDeleteIds.add(entry.id));
  ref.read(appDatabaseProvider).logEntriesDao.deleteEntry(entry.id);
  ```
  (keyed on the ENTRY so every slice disappears in the same frame — comment :199–200).
- Filtered in build BEFORE planning (day_view_screen.dart:137–141):
  ```dart
  _pendingDeleteIds.removeWhere((id) => !entries.any((e) => e.id == id));
  final visible = entries
      .where((e) => !_pendingDeleteIds.contains(e.id))
      .toList();
  ```

### Are interactions inside the segment or wrapped by the row?

They are built INSIDE `_segment` (a `_HourRow` method), but they operate entirely
through injected callbacks (`onEntryTap`, `onDeleteEntry`) and the `isToday` flag —
`_HourRow` holds no delete state itself. **Implication:** a shared segment widget
can own the `Dismissible` + `GlassCard.onTap` wiring and DELEGATE the effects via
`onEntryTap(entry)` / `onDeleteEntry(entry)` callbacks plus an `isToday`/
`allowSwipe` flag. All delete-state bookkeeping (`_pendingDeleteIds`) stays in the
caller's State.

---

## 5. The planner input/output (hour_row_planner.dart)

### Input record shape

`planHourRows` (hour_row_planner.dart:40) signature:
```dart
List<List<HourSegment>> planHourRows(
  List<PlanEntry> entries, {
  required DateTime day,
})
```
`PlanEntry` (hour_row_planner.dart:9):
```dart
typedef PlanEntry = ({int entryId, DateTime start, DateTime end});
```

### Return type

`List<List<HourSegment>>` — exactly 24 lists, index = hour 0..23, each sorted by
`startMin` (longer first on a tie). Per-hour element type `HourSegment`
(hour_row_planner.dart:12–20):
```dart
typedef HourSegment = ({
  int entryId,
  int startMin, // 0..59  offset within the hour
  int endMin,   // 1..60  offset within the hour (endMin > startMin)
  bool isFirstOfEntry, // this is the entry's earliest visible hour today
  bool isLastOfEntry,  // this is the entry's latest visible hour today
  int lane,      // 0-based lane within the hour (overlap resolution)
  int laneCount, // total lanes used in this hour (>=1)
});
```
Note: fields are `startMin`/`endMin` (not `startMin/endMin` durations) — offsets
WITHIN the hour, 0..60. Guarantees (docstring hour_row_planner.dart:37–39):
`0 <= startMin < endMin <= 60`, `0 <= lane < laneCount`, `laneCount >= 1`, no two
overlapping segments share a lane, exactly one `isFirstOfEntry` and one
`isLastOfEntry` per surviving entry.

### Purity

**Confirmed pure.** hour_row_planner.dart has no `import` statements at all (only
`library;` at :6). Docstring (:1–6) states it is deliberately kept free of
Flutter/Drift imports so it is directly unit-testable and importable from another
feature. The only non-public type is `_Slice` (an internal class). Callers map DB
rows onto `PlanEntry` before calling in. Safe to import from the Routine screen.

(routine_overlay_planner.dart is likewise pure — only `library;`, no imports —
exporting `PlanSlot`, `PlanLog`, `RoutineVerdict`, `HourRoutine`, `planRoutineEdges`.)

---

## 6. Data the row scaffolding needs vs. the caller supplies

| Scope | Datum | Source in code | Shareable / caller-specific |
|---|---|---|---|
| PER SEGMENT | `entryId` | `HourSegment.entryId` | generic (shareable) |
| PER SEGMENT | `startMin`, `endMin` | `HourSegment` | generic (shareable) |
| PER SEGMENT | `lane`, `laneCount` | `HourSegment` | generic (shareable) |
| PER SEGMENT | `isFirstOfEntry`, `isLastOfEntry` (corners + label-once) | `HourSegment` | generic (shareable) |
| PER SEGMENT | category color | `byCatId[entry.categoryId]?.colorValue ?? 0xFF607D8B` | generic (needs a color resolver injected) |
| PER SEGMENT | label text | `entry.description` | caller-specific (Day View reads `LogEntry`) |
| PER ROW | hour index `h` | `itemBuilder` index / `_HourRow.hour` | generic (shareable) |
| PER ROW | row height | `_rowHeight(rows, h) = _laneHeight * laneCount` | generic (shareable) |
| PER ROW | routine edge layer | `routineEdges?[h]` → `_routineEdge(...)` | caller-specific (Day View background layer) |
| PER ROW | now-line layer | `if (isCurrentHour) _nowLine(...)` | caller-specific (Day View foreground layer) |
| PER ROW | hour divider | inline in track Stack | generic (shareable) |
| GLOBAL | `isToday` | `_DayViewScreenState._isToday` | caller-specific flag (gates swipe + now-line) |
| GLOBAL | `now` | `DateTime.now()` in `_Timeline.build` | caller-specific (drives now-line) |
| GLOBAL | `byId` (`Map<int,LogEntry>`) | `_Timeline` | caller-specific (Day View data model) |
| GLOBAL | `byCatId` (`Map<int,Category>`) | `_Timeline` | caller-specific data, but color-lookup is generic |
| GLOBAL | tap / delete callbacks | `onEntryTap`, `onDeleteEntry` | caller-specific (Day View wiring) |

**Generic core:** the `HourSegment` geometry (left/width/top/height + corners),
the gutter, the track `LayoutBuilder`→`Stack`, the hour divider, and the segment
box. **Caller-specific:** the label content, the routine/now-line background
layers, the tap/swipe effects, and the `isToday`/`now` inputs.

---

## 7. Extraction risk check

### What the timeline reaches into `_DayViewScreenState`

| State member | File:line | Move into shared widget, or stay in Day View? |
|---|---|---|
| `_date` (`DateTime`) | :38 | STAY — Day View's shown date; pass `day` to the planner. |
| `_scrollCtrl` (`ScrollController`) | :39 | STAY — owned by Day View (initial jump-to-now); PASS into shared widget so it hosts the `ListView`. |
| `_pendingDeleteIds` (`Set<int>`) | :40 | STAY — optimistic-delete bookkeeping; filtered pre-plan (:137). Shared widget delegates deletes via callback. |
| `_ticker` (`Timer?`, 1-min) | :43,:53 | STAY — drives now-line `setState`. Shared widget is stateless w.r.t. the clock; caller passes `now`. |
| `_didInitialScroll` (`bool`) | :46 | STAY — one-shot scroll guard. |
| `_scheduleInitialScroll` (post-frame `jumpTo`) | :84–97 | STAY — depends on `_scrollCtrl` + `_rowHeight`; needs row heights, so pass a height accessor or keep in Day View. |
| `ref.watch(dayViewEntriesProvider(_date))` | :101 | STAY — provider read; feed resulting entries in. |
| `ref.watch(categoriesProvider)` | :102 | STAY — feed `cats` in. |
| `ref.watch(allRoutineSlotsProvider)` | :103 | STAY — Day-View-specific overlay source. |
| `ref.read(appDatabaseProvider).logEntriesDao.deleteEntry` | :202–206 | STAY — side effect behind `onDeleteEntry`. |
| `showModalBottomSheet` / `LogEntrySheet` | :191–197 | STAY — behind `onEntryTap`. |

The timeline body (`_Timeline` + `_HourRow`) already reaches into `_DayViewScreenState`
ONLY through constructor params — it holds no direct reference to the State,
provider, controller lifecycle, or timer. The seam is already clean: everything
stateful stays in `_DayViewScreenState`; the shared widget receives `rows`,
`byId`/`cats` (or a color+label resolver), the `scrollCtrl`, `isToday`, `now`,
optional per-row layer builders (routine edge, now-line), and the two callbacks.

### Regression-catching tests

| Test file | Asserts |
|---|---|
| [test/day_view_row_layout_test.dart](test/day_view_row_layout_test.dart) | Row geometry: all 24 rows render (:111); 60-min fills track / 30-min half / GlassCard fills slot (:122); 15-min true width + label (:152); tiny sliver floored to 48px and shifted in-bounds (:166); cross-midnight sleep as one continuous bar labelled once (:183); overlapping entries stack into lanes and grow the row by `_laneHeight` (:209); tap opens edit sheet (:240); swiping one segment removes every segment of the entry (:255); now-line offset `minute/60` in current hour (:277); no now-line on a past day (:303). |
| [test/day_view_routine_overlay_test.dart](test/day_view_routine_overlay_test.dart) | Routine overlay edge: edges only on covered hours (:165); inactive slot draws nothing (:185); day-of-week filter (:203); verdict→color/width green/amber/red/neutral (:226–338); 3-hour slot uniform color across rows (:340); edge sits behind segment and does not steal taps (:364). Keys used: `routine_edge_$hour`, `routine_accent_$hour`, `seg_${entryId}_${hour}_$lane`. |
| [test/hour_row_planner_test.dart](test/hour_row_planner_test.dart) | Pure planner slicing/lane math (unit). Not a render test, but any change to `HourSegment` shape breaks it. |

These three suites collectively pin: segment key format, geometry constants,
lane→height growth, corner/label-once behavior, swipe/tap wiring, now-line
placement, and the routine-edge key + color/width mapping. Any extraction must
keep the `seg_${entryId}_${hour}_$lane`, `routine_edge_$hour`, `routine_accent_$hour`,
and `now_line` keys intact or these fail.

---

## Verdict (seam for a shared widget)

Cleanest seam: a `HourTimeline` widget owning the `ListView.builder(itemCount:24)`
+ `_HourRow` scaffolding (gutter, track `LayoutBuilder`→`Stack`, hour divider, and
the `HourSegment`→Positioned geometry incl. `_laneHeight`/`_minSegWidth`/corners),
plus the `Dismissible`+`GlassCard.onTap` segment wiring driven by callbacks. It
should OWN the generic core and ACCEPT from callers: the planned `rows`, a
`scrollCtrl`, `isToday` + `now`, a per-segment color+label resolver (so it need not
know `LogEntry`/`Category`), `onEntryTap`/`onDeleteEntry` callbacks, and two
optional per-row layer builders — `backgroundLayer(hour)` for the routine edge and
`foregroundLayer(hour)` for the now-line — which Day View supplies and the Routine
screen can leave null or replace. Everything stateful (`_scrollCtrl` lifecycle,
`_ticker`, `_pendingDeleteIds`, providers, `_scheduleInitialScroll`) stays in the
hosting screen's State.
