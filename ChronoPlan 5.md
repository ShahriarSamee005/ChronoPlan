# ChronoPlan — Session Handoff (Chat 5)

This is the running context doc for ChronoPlan. Read it top to bottom before doing
anything. It covers what the app is, how it's built, what this chat built/fixed/
changed, what's still to build, the exact next step, and the working rules to
follow.

---

## 0. How we work together (the rules — follow these)

1. **Diagnose before fixing.** Never change code from assumptions. The first step
   for any fix or feature is a **read-only diagnostic** — a prompt that reads the
   real code and reports findings, changing nothing.
2. **Spec-first.** Lock exactly what we're building (behavior + the real
   decisions) before any code. Play the spec back for sign-off.
3. **Ask, don't assume.** When there's a real choice, ask — don't guess. Confirm
   scope before building.
4. **Ask permission before issuing any Claude Code prompt.**
5. **Phased builds with verification gates.** Break work into small phases; each
   Claude Code prompt ends with a **STOP and report**, and we verify before the
   next phase.
6. **Prompts are complete, pasteable markdown blocks** with an explicit "Do NOT"
   section and concrete verification steps (analyzer, tests, on-device checks).
7. **Modular / reuse existing patterns** rather than inventing parallel ones.
   Prefer extracting pure, testable functions (Flutter/Drift-free) like
   `planCarve` / `computeMissedHours`.
8. **Reactivity discipline** — rely on the provider chain; avoid `.invalidate()`
   as a band-aid.
9. **Reply in simpler, plain language.** Move fast once trade-offs are clear.
10. **Dev environment:** Windows + a physical Android device (`flutter run -d
    android`). Text pasting long reports into chat has been unreliable — prefer
    screenshots or a `.txt`/`.md` file, or have Claude Code self-verify.

---

## 1. What ChronoPlan is

A **Flutter (Android-first) app for hourly retrospective time logging with AI
coaching.** You log the hour that just ended, compare your real day against your
ideal routine, and get AI coaching. **You** decide whether a day was good (thumbs
up/down) — the app never hands out productivity verdicts.

**Core philosophy**
- Purely **retrospective** logging (log the hour that just ended).
- **No app-generated productivity judgments** — the user self-assesses.
- Every entry is an ordinary, fully-editable retrospective log. (The old "sacred
  real-time entry" concept was removed — `insertRealTime` is test-only; nothing
  in `lib/` creates real-time rows.)
- Sleep auto-insertion removed; there's a manual sun/moon sleep toggle.
- AI is centralized (no user API key).

**Stack**
- Flutter, Riverpod, Drift (SQLite, offline-first, **schemaVersion 7**).
- Supabase: anon auth + an Edge Function `groq-proxy` → Groq / Llama 3.1 8b.
- `flutter_local_notifications`, `fl_chart`.
- A hand-rolled **Kotlin `queryEvents` method channel** for per-hour usage stats.
- Glassmorphism, dark-first UI, Manrope font.
- Bottom nav: **Dashboard | Day View | [+ Log] | Routine | History** via
  `AppShell` `ShellRoute`.

**What was already built (before this chat)**
- Hourly logging; flexible categories (with a protected system "Screen Time"
  category).
- Routine builder + green/amber/red Day View comparison.
- Daily pie + weekly stacked bar (History).
- Swipe-to-delete + tap-to-edit on Day View.
- Per-day to-do list (`intention_tasks`); across-midnight handling
  (`currentDayProvider` + `AppShell` resume day-flip).
- AI: log parsing, category suggestion, weekly insight, streaming debrief with
  drill / friendly / neutral personas.

**Screen Time feature (what it is)** — an **honesty-layer confirm-into-log flow**,
NOT a stats dashboard. There is no "screen-on total / unattributed bucket."
`PACKAGE_USAGE_STATS` permission + the protected Screen Time category + a usage
service + a today-only debug view (long-press the "Screen Time" AppBar title).
Detected phone usage for an hour surfaces as a reconciliation item you confirm +
categorize (default Screen Time) or dismiss.
- **Over-counting blocker (fixed earlier):** a session-reconstruction bug was
  back-dating a lone unmatched BACKGROUND event to midnight (~20h phantoms). Fixed
  in `usage_stats_service.dart` (screen-on watermark / head-cap 90 min / drop +
  ≤60-min invariant guards; screen-off suspends, screen-on resumes).
  `test/usage_phantom_background_test.dart` is the acceptance spec.

---

## 2. What THIS chat did

### 2a. Screen Time reconciliation rework — ✅ DONE, device-verified, user-approved

**Why:** the shipped Screen Time flow had the wrong underlying model. The user's
confirmed model: **screen time is a separate OVERLAY on top of manual logging** —
confirming/carving screen time never counts as "the user accounted for this hour,"
and never erases a manual log.

**What was built (all analyzer-clean, tests green, verified on device):**

- **Provenance:** `BoolColumn isUsageDerived` on `LogEntries` (schema **6 → 7**,
  `addColumn` migration). Set `true` **only** on screen-time writes; manual /
  AI-parse / sleep / realtime stay `false`.
- **Split rule** — pure `planCarve()` @ `lib/core/usage_stats/carve_planner.dart`:
  screen time is added **in full** into the hour's empty space (tail-first, then
  head, ≤2 blocks); the logged entry is trimmed **only from its end** and **only**
  when logged + screen > 60 (down to `60 − screen`), keeps ≥1 min, start never
  moved, never erased/replaced.
- **Missing-hours** — pure `computeMissedHours()` @ `log_entry_sheet.dart`: ignores
  `isUsageDerived` rows, so a screen-time-only hour still reads as un-logged until
  a **manual** log.
- **Write paths:** `insertRetroactive` returns a record `{ids, requestedMinutes,
  writtenMinutes}` and takes an `avoidUsageDerived` flag. Manual `_save` uses it,
  so hand logs **fill around** existing screen time (splitting into the gaps); the
  sheet stays open only if the range is fully blocked. Empty-hour confirm writes
  only the **detected** minutes (`UsageSuggestion.totalMinutes`), top-anchored, so
  there's room to log later.
- **Shared confirm/dismiss** = `applyCarve` / `dismissCarve` @
  `lib/core/usage_stats/carve_actions.dart`.
- **Where reconciliation lives:** **ONLY in the card** (`usage_suggestions_card
  .dart`). **Day View has NO carve UI** — `entry_with_carves.dart` was **deleted**.
  The card shows empty-hour suggestions, then **one row per app-carve** (styled
  like the suggestion rows), each labeled `"App Nm · h a - h a"` (source hour).
- **Badge + card header** read `pending_reconciliation_provider` =
  `#empty-hour-suggestions + #distinct logged-entry-ids that still have carves`
  (counts **hours**, not rows).

**Original user-reported problems — all fixed:** short-entry tap not opening the
edit sheet (fixed via `Positioned.fill`); carve replacing the whole logged entry
(now splits); missing-hours cleared by a screen-time confirm (now only a manual
log clears it); manual log stacking on top of screen time (now fills around it);
and screen time surfaced cleanly in the card.

### 2b. Phase 3 "honesty layer" — ❌ DROPPED

An idea to have the AI debrief coach read screen time was considered and **dropped
by the user**. Debrief is unchanged; the coach gets no screen-time info.
(Side-finding, not fixed: the weekly-insight prompt claims "actual vs planned" but
is never actually sent routine data.)

### 2c. Day View redesign — 🚧 IN PROGRESS

The current Day View draws time **vertically** (24h-tall Stack, block height =
duration at 76 px/hr). Short blocks clip their labels — and after 2a, short blocks
became common. The user wants a **Google-Calendar-style** redesign: per-hour rows.

**Diagnostic done. Phase 1 (the pure slicing function) was built** — see §4 for
the exact next step (Phase 1 needs a pass-confirmation, Phase 2 is written).

---

## 3. Day View redesign — the locked spec

**Target layout:** replace the vertical Stack with **per-hour rows**. Each hour is
a row; within a row, blocks lay **left-to-right with width proportional to
minutes** (60 min = full row width). Multi-hour entries (e.g. sleep) appear as a
bar in **each hour they cover** (one entry underneath). The routine green/amber/red
overlay is **kept**.

**Locked decisions**
- **(D1) Truthful width with a minimum-width floor.** Width = minutes. Target:
  a **15-minute** block is readable at its true width; only sub-15 slivers (e.g.
  the trimmed edge of sleep) hit the min-width floor. If applying min-widths would
  overflow a row, rebalance gracefully — never an overflow error.
- **(D2) True partial width at multi-hour ends.** Middle hours of a span are full
  width; the first/last hours are drawn at their real partial width.
- **(D3) Keep swipe-to-delete per block**, made size-robust, deleting the **whole
  entry** (all its segments together). `_pendingDeleteIds` keys by **entry id**.
- **Overlaps stack vertically:** when an hour has >1 lane (overlapping entries),
  the extra lane(s) stack **below** within that hour, so the **row grows taller**
  (`rowHeight = laneHeight × laneCount`). Rows are therefore **variable height**
  (not a fixed `itemExtent`); compute scroll-to-now from cumulative row heights.
  Base `laneHeight ≈ 52px` (fits a 15-min block's label).
- Also: add a **now-line ticker** (the red line currently doesn't advance); stop
  drawing **deactivated** (`isActive=false`) routine slots (a small existing bug —
  Day View shows them, Routine doesn't); **drop the dead LIVE badge**
  (`insertRealTime` has no production call site, so it never shows).

**Structure:** `ListView.builder(itemCount: 24)` of `_HourRow` =
`[52px hour label][Expanded Stack: routine ghost layer (behind) + segments +
now-marker (only in the current hour's row)]`. Segments use the truthful-width +
min-width rule; lanes stack vertically.

**Pure function (Phase 1):** `planHourRows(entries, {day})` @
`lib/features/day_view/hour_row_planner.dart` (Flutter/Drift-free, like
`carve_planner.dart`), with `test/hour_row_planner_test.dart`. It:
1. clips each entry to `[day, day+24h)` in absolute DateTime (this fixes the
   broken midnight/sleep entry);
2. drops degenerate rows (`end <= start`);
3. slices per hour, tagging `isFirstOfEntry` / `isLastOfEntry` (label once; round
   only the outer corners so a span reads as one continuous bar);
4. assigns **lanes** per hour to resolve overlaps.
Returns 24 lists of `HourSegment {entryId, startMin, endMin, isFirstOfEntry,
isLastOfEntry, lane, laneCount}`.

**Key facts from the diagnostic (carry these forward):**
- Routine slots are **whole-hour only** (`startHour` 0–23, `durationHours` 1–4);
  "does slot cover hour h" is integer arithmetic. Verdict is computed **once per
  whole slot** (not per hour): green = coverage ≥0.75 **and** a category match;
  amber = coverage ≥0.10; red = <0.10; neutral (thin) if the slot isn't past yet.
  Keep that — paint the one verdict color on each row the slot covers.
- `_slotCoverage` works in minute-of-day, sums overlaps without unioning (can
  exceed 1.0), and **counts `isUsageDerived`** rows (unlike `computeMissedHours`).
- **Overlaps between logs are reachable** (manual-vs-manual, editing over a
  neighbor, AI-parse) — the layout must resolve them via lanes, never assume
  segments are disjoint.
- Keep `DayViewScreen` state (`_date`, `_scrollCtrl`, `_pendingDeleteIds`),
  the 3 provider reads, `_DateNav`, AppBar, `TimeGradientBackground`, and the
  loading/empty handling. Only the timeline body is rebuilt.

---

## 4. THE EXACT NEXT STEP

**Day View redesign is at Phase 1 → Phase 2.**

- **Phase 1** (`planHourRows` + tests) — a build prompt was issued. **Confirm it
  passed** (`flutter analyze` clean + `test/hour_row_planner_test.dart` green)
  before Phase 2. (The Phase 2 prompt below also re-checks Phase 1 itself as its
  first step, so it's safe either way.)
- **Phase 2** (row-based rendering, entries only — routine overlay comes in Phase
  3) — the full pasteable prompt is ready; it's reproduced in §6 below. Paste it
  into Claude Code. **Note:** routine colors are intentionally absent in Phase 2
  and return in Phase 3.
- **Phase 3** — routine ghost overlay per row (whole-hour predicate, verdict once
  per slot) + `isActive` filter + drop LIVE badge + polish.

---

## 5. Everything still to build

**Day View redesign**
- Phase 2 (render rows/segments; entries only) — prompt ready (§6).
- Phase 3 (routine overlay on the new rows + `isActive` filter + drop LIVE badge
  + polish).

**Deferred edges from the Screen Time work (pre-existing, no regression)**
- Only **one app** can be reconciled per logged hour before the
  "exactly-one-fully-contained-entry" gate closes (multi-app-per-hour /
  multi-hour / mid-hour manual entries can't fully reconcile yet).
- **AI-parse submit loop** discards `insertRetroactive`'s return, pops
  unconditionally, has no try/catch — harden it **before** ever opting it into
  `avoidUsageDerived` (otherwise a visible overlap becomes silent data loss).
- **11PM–midnight** hour never gets a suggestion/carve (providers are today-only,
  cap at `now.hour`). The card being empty 12–1 AM is correct, not a bug.

**Minor / cosmetic**
- Card header still reads "Screen Time Suggestions" / "Tap Confirm to log detected
  screen time" — reword now that it also holds carves.
- Weekly-insight prompt claims "actual vs planned" but is never sent routine data
  (separate pre-existing bug).

**Older backlog (not yet scheduled):** onboarding/first-run tour; routine builder
polish; Supabase sync layer; AI voice consistency; app labeling/filtering
robustness.

---

## 6. Phase 2 build prompt (ready to paste into Claude Code)

```markdown
# ChronoPlan — Day View redesign, Phase 2 of 3: row-based rendering (entries only)

Rebuild Day View's timeline as per-hour ROWS using planHourRows: each hour is a
row; blocks lay left-to-right by width (minutes); overlaps stack into extra lanes
that make the row taller. Entries only — the routine overlay returns in Phase 3.
STOP at the end and report.

## STEP 0 — verify Phase 1 first (gate)
Run `flutter analyze` and `flutter test test/hour_row_planner_test.dart`. If the
planner or its tests fail or are missing, STOP and report the failure — do NOT
start Phase 2. If green, proceed.

## KEEP unchanged
`DayViewScreen`/`_DayViewScreenState` state (`_date`, `_scrollCtrl`,
`_pendingDeleteIds`, `_isToday`, `_prevDay`/`_nextDay`), the 3 provider reads,
`_DateNav`, the AppBar, `TimeGradientBackground`, and the `entriesAsync.when`
loading/empty handling. Only the timeline BODY (`_Timeline`) is rebuilt.

## Sizing constants
- `laneHeight = 52.0` (one lane; tall enough for a 15-min block's label).
- `minSegWidth = 48.0` (floor for very short slivers; a 15-min block is well above
  this at true width, so it stays truthful).
- Keep the 52 px hour-label gutter and the 8 px right gutter.

## Build the new `_Timeline`
- Map entries to planner input and call
  `planHourRows(entries.map((e)=>(entryId:e.id, start:e.startTime, end:e.endTime)).toList(), day: date)`
  → `rows` (24 lists). Build a `Map<int,LogEntry> byId` for lookups.
- Per-hour height: `rowHeight(h) = laneHeight * max(1, laneCountOf(rows[h]))`
  (laneCount = max `laneCount` among that hour's segments, else 1 for empty hours).
- Use a `ListView.builder(controller: _scrollCtrl, itemCount: 24,
  padding: bottom 100)` (NOT itemExtent — rows vary in height). Each item is an
  `_HourRow`:
  `Row[ SizedBox(width:52, hour label "HH:00" top-aligned),
        Expanded(SizedBox(height: rowHeight(h),
          child: LayoutBuilder → Stack[ segments…, now-line? ])) ]`
- Segment positioning inside the Stack (W = LayoutBuilder maxWidth):
  - `left = startMin/60 * W`
  - `width = max(minSegWidth, (endMin-startMin)/60 * W)`, then clamp so
    `left + width <= W` (shift left back if a floored sliver would overflow).
  - `top = lane * laneHeight`, `height = laneHeight - 4` (a 4 px vertical gap
    between stacked lanes).
  - Wrap in the segment widget below.
- Segment widget = the old entry-block look: `GlassCard(borderRadius: rounded
  per corner, fillColor: color@0.22, borderColor: color@0.55, blurSigma:6,
  padding: h8/v4)` where `color = Color(byId[seg.entryId]?.category…colorValue ??
  0xFF607D8B)`. Show the description text (white, 11, w600, ellipsis, maxLines 2)
  ONLY when `seg.isFirstOfEntry` (so a multi-hour entry is labelled once).
  Corner rounding: round the LEFT corners only when `isFirstOfEntry`, the RIGHT
  corners only when `isLastOfEntry`, else square — so a spanning entry reads as
  one continuous bar across rows. (Single-hour entry = all corners rounded.)
- Empty hours still render (empty row at base height) so all 24 rows show.

## Interactions (keep parity)
- Tap a segment → `onEntryTap(byId[seg.entryId])` → the existing
  `LogEntrySheet(existing:)` sheet. Unchanged plumbing.
- Swipe-to-delete per block: wrap each segment in a `Dismissible`,
  `direction: isToday ? endToStart : none`, `resizeDuration: null`,
  key `ValueKey('seg_${seg.entryId}_${h}_${seg.lane}')` (unique per segment),
  `onDismissed: (_) => onDeleteEntry(byId[seg.entryId])`. onDeleteEntry must add
  the ENTRY id to `_pendingDeleteIds` (as today) so ALL segments of that entry
  vanish together; keep the existing `_pendingDeleteIds` filtering in build.
  Keep the red delete background (centerRight icon).

## Now-line + ticker
- Only in the CURRENT hour's row when `isToday`: a full-height vertical red line
  at `left = nowMinuteInHour/60 * W` (a 1.5 px line; a small dot at top is fine),
  drawn last in that row's Stack.
- Add a `Timer.periodic(1 min)` in `_DayViewScreenState` that `setState`s so the
  line advances and the current-hour row updates; cancel it in `dispose`. Only
  needed while `isToday`.

## Initial scroll (variable heights)
- After the first frame WITH data, compute the cumulative height of hours before
  `(now.hour - 2).clamp(0,23)` (sum of `rowHeight(h)` for h < target) and
  `_scrollCtrl.jumpTo(offset)` — GUARD with `if (_scrollCtrl.hasClients)`. One-
  shot; don't fight later scrolls. (This replaces the old post-frame animateTo.)

## Do NOT
- Do NOT render the routine ghost/overlay or the green/amber/red edges (Phase 3).
- Do NOT change planHourRows, providers, LogEntrySheet, or the delete DB call.
- Do NOT produce overflow errors — clamp widths; lanes handle vertical overlap.
- Do NOT keep the old 76 px vertical Stack / SizedBox(1825).
- Do NOT reintroduce carve UI.

## Verification
- `flutter analyze` clean; `flutter test` — all green (report count).
- On-device (screenshot if possible):
  - each hour is a row; a 30/60-min log fills half/all of the row width;
  - a 15-min block shows its label; a tiny sliver shows floored but tappable;
  - a multi-hour / sleep entry now shows as a continuous bar across its hours
    (no more 6 px sliver; no missing-after-midnight);
  - two overlapping entries in an hour stack (row is taller), neither clipped;
  - tap opens the edit sheet; swipe deletes the whole entry;
  - the red now-line sits at the right spot and advances;
  - opening Day View lands scrolled near the current hour;
  - (routine colors are absent this phase — expected).

## Report back, then STOP.
```

---

## 7. Key code anchors

- `lib/features/day_view/day_view_screen.dart` — Day View (~497 lines; being
  rebuilt). `_hourPx=76` (old vertical scale).
- `lib/features/day_view/hour_row_planner.dart` — **new** pure slicing function
  (Phase 1).
- `lib/core/usage_stats/carve_planner.dart` — `planCarve()` (pure).
- `lib/core/usage_stats/carve_actions.dart` — `applyCarve` / `dismissCarve`.
- `lib/features/dashboard/widgets/usage_suggestions_card.dart` — the card that
  holds both empty-hour suggestions and per-app carve rows.
- `lib/providers/pending_reconciliation_provider.dart` — the badge/header count.
- `lib/providers/usage_suggestions_provider.dart`,
  `lib/providers/carve_proposals_provider.dart` — the two proposal sources.
- `lib/features/log_entry/log_entry_sheet.dart` — the log/edit sheet; contains
  `computeMissedHours` and the `_save` path.
- `lib/core/database/daos/log_entries_dao.dart` — `insertRetroactive`
  (record return + `avoidUsageDerived`), `_gaps`, `_blockers`.
- `lib/core/database/tables/log_entries_table.dart` — `isUsageDerived` column.
- `lib/features/routine/routine_screen.dart` — routine editor (`_hourPx=72`).
- Tests: `test/plan_carve_test.dart`, `test/carve_logic_test.dart`,
  `test/missed_hours_test.dart`, `test/insert_retroactive_test.dart`,
  `test/hour_row_planner_test.dart`, `test/usage_phantom_background_test.dart`.

---

## 8. Dev / infra notes

- Supabase Singapore region, anon auth; `ai_usage` table enforces 100 req/user/day.
  Free tier pauses after ~1 week of inactivity → AI downtime + host-lookup
  warnings (non-fatal).
- Dev: Windows + physical Android (`flutter run -d android`). Delete any stray
  `web/` folder; keep the project on a short, non-OneDrive path. Gradle:
  `org.gradle.parallel=false`, `kotlin.incremental=false`.
- Bottom sheets need `useRootNavigator: true`.
- There is **no Drift migration-test harness** — schema migrations are unverified
  by automated tests; device-test that an existing install still opens with data
  intact after a schema bump.
- After any Drift schema/table change, regenerate:
  `flutter pub run build_runner build --delete-conflicting-outputs`.

---

*End of handoff. Resume at §4 (confirm Phase 1, then paste the Phase 2 prompt from
§6).*
