# ChronoPlan — Day View Phase 2 pre-check (read-only diagnostic)

Generated 2026-08-25. No code was changed. Source files read:

- `lib/features/day_view/day_view_screen.dart` (497 lines)
- `lib/features/day_view/hour_row_planner.dart` (Phase 1 output)
- `lib/core/theme/glass_card.dart`
- `lib/providers/log_entries_provider.dart`, `lib/providers/categories_provider.dart`
- `lib/core/database/tables/log_entries_table.dart`, `.../categories_table.dart`
- `lib/core/database/daos/log_entries_dao.dart`
- `lib/core/database/app_database.g.dart` (generated data class names)

---

## A. State & scaffold — `_DayViewScreenState`

### A1. State fields

The class holds **four** members (three fields + one static const). All six names
in the brief exist; three of them are methods/getters, not fields.

```dart
class _DayViewScreenState extends ConsumerState<DayViewScreen> {
  late DateTime _date;
  static const double _hourPx = 76.0;
  final _scrollCtrl = ScrollController();
  final Set<int> _pendingDeleteIds = {};
```

| Name | Kind | Type |
| --- | --- | --- |
| `_date` | field | `DateTime` (`late`) |
| `_hourPx` | static const | `double` = `76.0` |
| `_scrollCtrl` | field | `ScrollController` |
| `_pendingDeleteIds` | field | `Set<int>` |
| `_isToday` | **getter**, not a field | `bool` |
| `_prevDay` | **method**, not a field | `void Function()` |
| `_nextDay` | **method**, not a field | `void Function()` |

```dart
  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  void _prevDay() =>
      setState(() => _date = _date.subtract(const Duration(days: 1)));

  void _nextDay() {
    final candidate = _date.add(const Duration(days: 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!candidate.isAfter(today)) setState(() => _date = candidate);
  }
```

There is **no** `_selectedHour`, no expansion state, and no per-row state of any
kind — Phase 2 adds the first of those.

`initState` also holds a scroll-position calculation that is coupled to `_hourPx`
and will break when row heights change:

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scrollTo = ((now.hour - 2).clamp(0, 21)) * _hourPx;
      _scrollCtrl.animateTo(scrollTo, ...);
    });
```

### A2. Provider reads in `build`

Three `ref.watch` calls at the top of `build`, plus a fourth `ref.read` inside the
delete callback.

```dart
    final entriesAsync = ref.watch(logEntriesForDayProvider(_date));
    final catsAsync    = ref.watch(categoriesProvider);
    final routineAsync = ref.watch(allRoutineSlotsProvider);
```

| Provider | Access | Yields |
| --- | --- | --- |
| `logEntriesForDayProvider(_date)` | `ref.watch` | `AsyncValue<List<LogEntry>>` |
| `categoriesProvider` | `ref.watch` | `AsyncValue<List<Category>>` |
| `allRoutineSlotsProvider` | `ref.watch` | `AsyncValue<List<RoutineSlot>>` |
| `appDatabaseProvider` | `ref.read` (inside `onDeleteEntry`) | `AppDatabase` |

Only the entries provider goes through `.when(...)`. The other two are unwrapped
with `.valueOrNull ?? []`, so categories and routine slots never gate the UI:

```dart
    final todaySlots = (routineAsync.valueOrNull ?? [])
        .where((s) => s.dayOfWeek == dayOfWeek || s.dayOfWeek == 0)
        .toList();
```

### A3. Build skeleton

Yes — `entriesAsync.when(data/loading/error)`. `_DateNav` is the AppBar `title`;
`TimeGradientBackground` is the `body`, wrapping a `SafeArea` that contains the
`.when`.

```dart
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: context.canPop() ? IconButton(...) : null,
        title: _DateNav(
          date: _date,
          onPrev: _prevDay,
          onNext: _nextDay,
          canGoNext: !_isToday,
        ),
        centerTitle: true,
        actions: [ IconButton(... context.push('/profile')) ],
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: entriesAsync.when(
            data: (entries) { ... return _Timeline(...); },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('$e', style: const TextStyle(color: Colors.white54)),
            ),
          ),
        ),
      ),
    );
```

`_DateNav` is a private `StatelessWidget` in the same file (lines 151–198) and is
independent of the timeline — Phase 2 does not need to touch it.

---

## B. Current timeline body (what Phase 2 replaces)

### B4. The timeline widget

`_Timeline`, a private `StatelessWidget` in the same file (lines 202–497). It is
invoked once, from the `data:` branch:

```dart
              return _Timeline(
                date: _date,
                entries: visible,
                cats: catsAsync.valueOrNull ?? [],
                routineSlots: todaySlots,
                isToday: _isToday,
                scrollCtrl: _scrollCtrl,
                hourPx: _hourPx,
                onEntryTap: (entry) => showModalBottomSheet(...),
                onDeleteEntry: (entry) { ... },
              );
```

Its full field list (the Phase 2 replacement's contract, if kept):

```dart
  final DateTime date;
  final List<LogEntry> entries;
  final List<Category> cats;
  final List<RoutineSlot> routineSlots;
  final bool isToday;
  final ScrollController scrollCtrl;
  final double hourPx;
  final void Function(LogEntry) onEntryTap;
  final void Function(LogEntry) onDeleteEntry;
```

### B5. The old vertical scale

```dart
  static const double _hourPx = 76.0;
```

```dart
    return SingleChildScrollView(
      controller: scrollCtrl,
      padding: const EdgeInsets.only(bottom: 100),
      child: SizedBox(
        height: hourPx * 24 + 1,
```

`76.0 * 24 + 1` = **1825.0** — matches the expected ~1825.

Layout is a `Row` of a fixed 52 px hour-label gutter (a `Stack` of 25 `Positioned`
labels) and an `Expanded` `Stack` holding, in paint order: 24 hour dividers,
24 half-hour dividers, routine ghost blocks, entry blocks, then the now-line.
Everything is absolute `Positioned` math against `hourPx` — there are no rows.

### B6. `_entryBlock`

```dart
  Widget _entryBlock(LogEntry entry) {
    final startMin = entry.startTime.hour * 60 + entry.startTime.minute;
    // Clamp end to midnight (1440 min) in case entry spans day boundary
    final endMin = (entry.endTime.hour * 60 + entry.endTime.minute)
        .clamp(startMin + 1, 1440);
    final top = startMin * hourPx / 60;
    final height =
        ((endMin - startMin) * hourPx / 60 - 2).clamp(6.0, double.infinity);

    final cat = cats.where((c) => c.id == entry.categoryId).firstOrNull;
    final color = Color(cat?.colorValue ?? 0xFF607D8B);

    final base = Dismissible(
      key: ValueKey('logentry_${entry.id}'),
      direction: isToday ? DismissDirection.endToStart : DismissDirection.none,
      resizeDuration: null,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.redAccent, size: 18),
      ),
      onDismissed: (_) => onDeleteEntry(entry),
      child: GestureDetector(
        onTap: () => onEntryTap(entry),
        child: GlassCard(
          borderRadius: 8,
          opacity: 0.13,
          blurSigma: 6,
          fillColor: color.withValues(alpha: 0.22),
          borderColor: color.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(...),   // description text + optional "LIVE" pill
        ),
      ),
    );

    return Positioned(top: top + 1, left: 2, right: 2, height: height, child: base);
  }
```

**Category color — the exact accessor path.** This is *not* a nested accessor on
the entry. `LogEntry` carries only a nullable **`categoryId`**; the color is
resolved by looking that id up in the separately-watched `cats` list:

```dart
    final cat = cats.where((c) => c.id == entry.categoryId).firstOrNull;
    final color = Color(cat?.colorValue ?? 0xFF607D8B);
```

- `entry.categoryId` → `int?`
- `cat` → `Category?` (Drift data class)
- `cat.colorValue` → **`int`** (non-nullable on `Category`; stored `0xFFRRGGBB`)
- fallback `0xFF607D8B` (blue-grey) is applied to the *int*, then wrapped in `Color`

So the literal expression Phase 2 must reuse is
`Color(cats.where((c) => c.id == entry.categoryId).firstOrNull?.colorValue ?? 0xFF607D8B)`,
and the `cats` list must be threaded into whatever renders a segment.

**`GlassCard` params passed:** `borderRadius: 8`, `opacity: 0.13`, `blurSigma: 6`,
`fillColor: color.withValues(alpha: 0.22)`, `borderColor: color.withValues(alpha: 0.55)`,
`padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)`.
Note: `opacity: 0.13` is **dead here** — see C9, `fillColor` takes precedence.

**Tap handler.** `GestureDetector(onTap:)` → the `onEntryTap` callback → in
`build`:

```dart
                onEntryTap: (entry) => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useRootNavigator: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => LogEntrySheet(existing: entry),
                ),
```

`GlassCard` has its own `onTap` param, but this code does **not** use it — the tap
is on an outer `GestureDetector`. Either works in Phase 2.

**Dismissible.** Key `ValueKey('logentry_${entry.id}')`; direction is
`endToStart` **only when `isToday`**, otherwise `DismissDirection.none` (past days
are not swipe-deletable); `resizeDuration: null` so no collapse animation;
`onDismissed: (_) => onDeleteEntry(entry)`.

**`_pendingDeleteIds` lifecycle.** Added in the delete callback, and reconciled +
filtered at the top of the `data:` branch:

```dart
                onDeleteEntry: (entry) {
                  setState(() => _pendingDeleteIds.add(entry.id));
                  ref.read(appDatabaseProvider).logEntriesDao.deleteEntry(entry.id);
                },
```

```dart
            data: (entries) {
              _pendingDeleteIds
                  .removeWhere((id) => !entries.any((e) => e.id == id));
              final visible = entries
                  .where((e) => !_pendingDeleteIds.contains(e.id))
                  .toList();
```

The `removeWhere` self-heals the set once the DB stream catches up. This pattern
is orthogonal to the timeline rewrite and should be preserved verbatim.

### B7. Now-line and tickers

Drawn as a `Positioned` dot + line inside the timeline `Stack`, from a `nowMinute`
computed **once per build**:

```dart
    final now = DateTime.now();
    final nowMinute = isToday ? now.hour * 60 + now.minute : -1;
```

```dart
                  if (nowMinute >= 0)
                    Positioned(
                      top: nowMinute * hourPx / 60 - 1,
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          Container(
                            width: 9, height: 9,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent, shape: BoxShape.circle),
                          ),
                          Expanded(
                            child: Container(height: 1.5, color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
```

**Timer / ticker: NO.** `day_view_screen.dart` does not import `dart:async` and
contains no `Timer`, no `Ticker`, and no `AnimationController` (grep for
`Timer|Ticker|dart:async` returns nothing). The red line only moves when the
widget happens to rebuild — i.e. on a DB stream event or a date change. If Phase 2
wants a live-advancing now-line it must add the first ticker in this screen, along
with its `dispose`.

`DateTime.now()` is additionally called in `_ghostBlock` (line 366) for the
past/future ghost styling, so "now" is sampled in two independent places.

---

## C. Types & widget APIs

### C8. The entry type

**`LogEntry`** — a Drift-generated data class
(`app_database.g.dart:634: class LogEntry extends DataClass implements Insertable<LogEntry>`),
generated from:

```dart
class LogEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get description => text().withDefault(const Constant(''))();
  // Nullable FK → categories.id (enforced at app layer)
  IntColumn get categoryId => integer().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  BoolColumn get isRealTime => boolean().withDefault(const Constant(false))();
  BoolColumn get isAiParsed => boolean().withDefault(const Constant(false))();
  BoolColumn get isUsageDerived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  TextColumn get userId => text().nullable()();
  TextColumn get syncId => text().nullable()();
}
```

| Need | Field | Type |
| --- | --- | --- |
| id | `entry.id` | `int` |
| start | **`entry.startTime`** | `DateTime` |
| end | **`entry.endTime`** | `DateTime` |
| category | **`entry.categoryId`** — id only, `int?` | no nested object |

Confirmed: it is `startTime`/`endTime`, **not** `start`/`end`.

**Category is id-only.** There is no `entry.category`. The colour lives on the
separate `Category` data class (`app_database.g.dart:159`), field **`colorValue`**,
type **`int`** (non-nullable), documented as `0xFFRRGGBB`:

```dart
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  IntColumn get colorValue => integer()(); // 0xFFRRGGBB
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  ...
}
```

Provider chain: `logEntriesForDayProvider` is a `StreamProvider.family`:

```dart
final logEntriesForDayProvider =
    StreamProvider.family<List<LogEntry>, DateTime>((ref, date) {
  return ref.watch(appDatabaseProvider).logEntriesDao.watchForDay(date);
});
```

```dart
final categoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(appDatabaseProvider).categoriesDao.watchAll();
});
```

### C9. `GlassCard` constructor

`lib/core/theme/glass_card.dart`. All five names in the brief are real, plus four
more:

```dart
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double opacity;
  final double blurSigma;
  final EdgeInsets? padding;
  final Color? borderColor;
  final Color? fillColor;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.opacity = 0.12,
    this.blurSigma = 10,
    this.padding,
    this.borderColor,
    this.fillColor,
    this.onTap,
    this.width,
    this.height,
  });
```

| Param | Type | Default |
| --- | --- | --- |
| `child` | `Widget` | **required** |
| `borderRadius` | `double` | `20` |
| `opacity` | `double` | `0.12` |
| `blurSigma` | `double` | `10` |
| `padding` | `EdgeInsets?` | `null` |
| `borderColor` | `Color?` | `null` → `AppColors.glassBorder` |
| `fillColor` | `Color?` | `null` → `Colors.white.withValues(alpha: opacity)` |
| `onTap` | `VoidCallback?` | `null` |
| `width` / `height` | `double?` | `null` |

Confirmed: `padding` is `EdgeInsets?`, **not** `EdgeInsetsGeometry?` — passing a
`EdgeInsets.symmetric(...)` is fine, passing `EdgeInsetsDirectional` is not.

Two behaviours Phase 2 should know:

1. **`fillColor` wins over `opacity`.** `color: fillColor ?? Colors.white.withValues(alpha: opacity)` — so the existing `opacity: 0.13` on `_entryBlock` is inert. Don't carry it forward and assume it does anything.
2. **The border is always 1 px on all four sides** (`Border.all(..., width: 1)`). There is no left-accent-bar option. A per-segment coloured left edge (the natural way to signal "continues from the previous hour") needs a plain `Container`/`DecoratedBox` like `_ghostBlock` uses, not `GlassCard`.

Also relevant to per-row rendering: `GlassCard` wraps every instance in a
`BackdropFilter`. 24 rows × N segments each is a lot more `BackdropFilter` layers
than the current flat `Stack` produces — worth watching for frame drops, which the
class doc itself calls out.

---

## D. Import + planner API

### D10. Confirmed

`lib/features/day_view/hour_row_planner.dart` exists (Phase 1). Since the consumer
`day_view_screen.dart` sits in the **same directory**, and this file's existing
imports are all relative (`import '../../core/theme/glass_card.dart';`), the
in-style import is:

```dart
import 'hour_row_planner.dart';
```

The package-absolute form
`package:chronoplan/features/day_view/hour_row_planner.dart` also resolves and is
what the test file uses, but it would be the only package-absolute import in
`day_view_screen.dart`. **Recommend the relative form for the screen.**

Actual API, verbatim:

```dart
typedef PlanEntry = ({int entryId, DateTime start, DateTime end});

typedef HourSegment = ({
  int entryId,
  int startMin,
  int endMin,
  bool isFirstOfEntry,
  bool isLastOfEntry,
  int lane,
  int laneCount,
});

List<List<HourSegment>> planHourRows(
  List<PlanEntry> entries, {
  required DateTime day,
})
```

Record field names are exactly `entryId`, `start`, `end` — so the assumed mapping
`(entryId: e.id, start: e.startTime, end: e.endTime)` compiles as written.

Note the planner returns `HourSegment`s carrying only `entryId`, not the entry
itself. Phase 2 needs an `id -> LogEntry` lookup map to render descriptions,
colours, the LIVE pill, and to feed `onEntryTap` / `onDeleteEntry`.

---

## E. Mismatches against the Phase 2 assumptions

| # | Assumption | Reality | Severity |
| --- | --- | --- | --- |
| 1 | `(entryId: e.id, start: e.startTime, end: e.endTime)` | ✅ Matches exactly | — |
| 2 | Color via nullable category accessor + grey fallback | ⚠️ Shape differs | **Medium** |
| 3 | Tap → `LogEntrySheet(existing:)` | ✅ Matches exactly | — |
| 4 | Delete via `_pendingDeleteIds` + DB delete | ✅ Matches exactly | — |

### E-1 ✅ Entry mapping — matches

`LogEntry.id` is `int`, `startTime`/`endTime` are non-nullable `DateTime`. The
mapping compiles as assumed.

### E-2 ⚠️ Category colour is a **lookup**, not an accessor

The assumption was `entry.category?.colorValue`. There is no `category` object on
`LogEntry` — only `categoryId` (`int?`). The colour comes from a *second* provider:

```dart
    final cat = cats.where((c) => c.id == entry.categoryId).firstOrNull;
    final color = Color(cat?.colorValue ?? 0xFF607D8B);
```

Consequences for Phase 2:
- the `cats` list must be threaded down to whatever renders a segment;
- the grey fallback is `0xFF607D8B` applied to the **int**, not to a `Color`;
- `colorValue` itself is non-nullable — the `?.` is on `cat`, not on the field;
- a linear `.where(...).firstOrNull` per entry was cheap when there was one block
  per entry. With per-hour slicing a 3-hour entry is now looked up 3×. Build an
  `{int: Category}` map once per build instead.

### E-3 ✅ Tap — matches

`showModalBottomSheet(..., useRootNavigator: true, backgroundColor: Colors.transparent, builder: (_) => LogEntrySheet(existing: entry))`, exactly as assumed. The callback lives in `build`, so it survives the `_Timeline` rewrite untouched.

### E-4 ✅ Delete — matches

`setState(() => _pendingDeleteIds.add(entry.id))` then
`ref.read(appDatabaseProvider).logEntriesDao.deleteEntry(entry.id)`
(`Future<void> deleteEntry(int id) => (delete(logEntries)..where((e) => e.id.equals(id))).go();`).
Exactly as assumed.

---

## E-extra. Things the Phase 2 brief did not account for

These are not assumption mismatches, but they will bite during the build.

### (a) 🔴 `watchForDay` filters on `startTime` only — the sleep block never arrives

```dart
  Stream<List<LogEntry>> watchForDay(DateTime date) {
    final start = _dayStart(date);
    final end = start.add(const Duration(days: 1));
    return (select(logEntries)
          ..where((e) =>
              e.startTime.isBiggerOrEqualValue(start) &
              e.startTime.isSmallerThanValue(end))
          ..orderBy([(e) => OrderingTerm(expression: e.startTime)]))
        .watch();
  }
```

The planner clips correctly in **both** directions, but the query only supplies
entries whose **start** falls inside the day. So:

- an entry `[today 23:30 → tomorrow 01:00]` **is** returned → planner clips it to
  hour 23 → the midnight-sliver fix works. ✅
- an entry `[yesterday 23:00 → today 06:45]` (the sleep block) is **not** returned
  at all → hours 0–6 render empty today. ❌

The planner's previous-day clipping path is therefore currently unreachable from
the real Day View. If Phase 2 is meant to show last night's sleep in today's early
rows, `watchForDay` (or a new provider) has to widen to overlap semantics —
`startTime < end && endTime > start`. **That is a DAO change and is out of Phase 2
scope as written; flagging it as a decision, not doing it.**

### (b) The routine ghost-block layer has no place in a row layout

`_ghostBlock` (lines 356–409) plus its two helpers `_slotCoverage` (327–342) and
`_hasCategoryMatch` (344–354) — ~85 lines — paint a background layer of routine
slots with green/amber/red left edges scoring past adherence. This is absolute
`Positioned` math against `hourPx` and does not survive a row rewrite as-is.
`RoutineSlot` is hour-granular (`startHour`, `durationHours`, `dayOfWeek`,
`categoryId`), which actually maps onto hour rows cleanly — but the brief says
nothing about it. **Needs a decision: port to rows, drop, or leave the timeline
in place behind a flag.**

### (c) The `initState` auto-scroll is hard-coded to `_hourPx`

`((now.hour - 2).clamp(0, 21)) * _hourPx` assumes a uniform 76 px per hour. If
Phase 2 rows vary in height (e.g. expanded current hour, or lane-count-driven
heights), this must become a key/index-based scroll — `ScrollablePositionedList`,
or a `GlobalKey` on the target row + `Scrollable.ensureVisible`.

### (d) Sub-hour segments are ~1.2 px tall at the current scale

The old code clamps block height to a 6 px floor
(`.clamp(6.0, double.infinity)`). Per-hour rows need their own minimum-height rule
for short segments, plus a decision on what a `laneCount: 3` hour looks like
(three narrow columns vs. a stacked/summary row). The planner supplies `lane` and
`laneCount`; it takes no position on pixels.

### (e) `_Timeline` is a `StatelessWidget`

Per-hour expand/collapse or a live now-line means it becomes stateful, or the
state is hoisted into `_DayViewScreenState`. Hoisting is the better fit — the
screen already owns `_scrollCtrl` and `_pendingDeleteIds`.

---

## Quick reference for the Phase 2 build

```dart
// import (matches file's existing relative style)
import 'hour_row_planner.dart';

// mapping — compiles as-is
final rows = planHourRows(
  [for (final e in visible) (entryId: e.id, start: e.startTime, end: e.endTime)],
  day: _date,
);

// entry + category lookup (build these once per build, not per segment)
final byId    = {for (final e in visible) e.id: e};
final catById = {for (final c in cats) c.id: c};

// colour for a segment
final entry = byId[seg.entryId]!;
final color = Color(catById[entry.categoryId]?.colorValue ?? 0xFF607D8B);
```

**STOP — no code was written. Phase 2 not started.**
