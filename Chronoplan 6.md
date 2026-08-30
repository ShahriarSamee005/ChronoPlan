# ChronoPlan — Session Handoff (Chat 6)

A handoff document so a fresh chat can pick up ChronoPlan development with full
context. **ChronoPlan is a Flutter Android app** for hourly retrospective
time-logging, routine comparison, and AI-driven productivity coaching. This
document covers: the app's core context, what this session (chat 6) built/fixed/
changed, the current state, everything still left to build and fix, and the
working conventions to follow.

> This is the chat-6 handoff. Prior handoffs are `ChronoPlan_1.md` … `_5.md`.
> The headline of this session: **the Day View redesign (row-based layout) is
> now fully complete and device-verified.**

---

## 1. What ChronoPlan is (core context)

**Core concept**
- Tracks how the day is spent in **hourly increments**, compares it against a
  user-defined **ideal routine**, and gives AI coaching on the gap.
- **The user — not the app — decides whether a day was good** (thumbs up/down; no
  app-generated score or verdict).
- Fundamental log model: at any moment past the top of an hour, the user logs
  *the hour that just ended*. **No future logging.** Missed hours surface as
  retroactive opportunities, never as "lateness."
- **Every entry is an ordinary, fully-editable retrospective record.** (The old
  "real-time entries are sacred/immovable" idea was removed in a prior session.)

**Already built before this session**
- **Time logging:** hourly / custom-interval reminders, silent notifications,
  contextual quotes, missed-hours strip, free-text + one category tag per entry.
- **Flexible categories:** user-created, colour-coded, archivable; a protected
  "Screen Time" system category; AI keyword auto-suggestion.
- **Sleep mode:** manual sun/moon toggle only; a "still sleeping?" courtesy
  notification with no data side-effects (auto-detection was removed).
- **Routine builder & comparison:** day-at-a-time timeline, copy-to-days; the
  green/amber/red comparison verdict.
- **Visualizations:** daily pie (Dashboard); weekly stacked bar chart
  (History/Reports, `fl_chart`, Sun–Sat, trend row, drill-down by day).
- **Daily Intention → to-do list** (chat 3): per-day task list (`intention_tasks`),
  single flagged task, swipe done/remove, roll-forward carry-over.
- **AI features:** **Groq + Llama 3.1 8b Instant**, proxied through a Supabase Edge
  Function (`groq-proxy`), Supabase anonymous auth, 100 req/user/day quota, no user
  API key, selectable coach persona (Drill Sergeant / Friendly Coach / Neutral
  Analyst), graceful offline fallback.
- **Usage Stats over-counting bug** — FIXED in chat 4 (foreground-session
  reconstruction; the app was over-counting because sessions weren't closed on
  screen-off).
- **Screen Time reconciliation rework** (chat 5): provenance flag added,
  `planCarve`, Screen Time treated as an overlay; **schema bumped 6 → 7**.

**Tech stack**
- Flutter (Android first), Riverpod, Drift (SQLite, offline-first), Supabase
  (anon auth + Edge Functions + Postgres), `flutter_local_notifications`, `fl_chart`.
- Android per-hour usage uses a **hand-rolled Kotlin `queryEvents` method channel**
  (the `app_usage` package only returns daily aggregates, unusable per-hour).
- **Drift schema version: 7** (no schema change this session).

**UI direction**
- Glassmorphism, dark-mode-first. Semi-transparent `GlassCard`s (blur + rounded).
- **Time-of-day dynamic background gradient.** Manrope typography.
  Colourblind-aware category palette.
- Bottom nav: Dashboard | Day View | [+ Log] | Routine | History. `AppShell`
  hosts the nav as a persistent `ShellRoute`; full-page routes push on top.
- `GlassCard` note discovered this session: its `borderRadius` param is a **`double`**
  (feeds `BorderRadius.circular()`), it exposes `width`/`height`/`onTap`, its own
  inner detector is opaque (so wrap taps via `GlassCard.onTap`, not an outer
  `GestureDetector`), and its `opacity` param is inert when `fillColor` is set.

---

## 2. What this session (chat 6) built / fixed / changed

The whole session completed the **Day View redesign**: replacing the old fixed
76px vertical stack with a **Google-Calendar-style per-hour ROW layout**, then
rebuilding the routine overlay on top of it. It was done in gated phases; the last
several caught real render bugs along the way.

### 2a. Phase 1 — pure per-hour slicing planner — ✅ (carried from chat 5, verified here)
`lib/features/day_view/hour_row_planner.dart` — a **pure, Flutter/Drift-free**
`planHourRows(entries, {day})` returning **24 per-hour lists** of `HourSegment`s.
Slices each entry into the hours it touches, clips to the day, drops degenerate/
other-day rows, and packs overlaps into **lanes**. Works in integer minutes from
midnight for exact hour boundaries. Guarantees per hour: uniform `laneCount`,
exactly one `isFirstOfEntry`/`isLastOfEntry` per entry. **14 tests.**

### 2b. Phase 1.5 — cross-midnight overlap query — ✅ COMPLETE
Root problem: the Day View entries query filtered on **start time only**, so last
night's sleep (`23:00 → 06:45 today`) never reached the planner and today's early
rows stayed empty.

- Added `watchEntriesOverlappingDay(date)` to `log_entries_dao.dart` — predicate
  `startTime < dayEnd && endTime > dayStart` (overlap), ordered by `startTime`,
  mirroring the file's existing `_blockers` overlap style.
- **`watchForDay` left untouched** (it has other consumers). The entries provider
  swap was deferred to Phase 2 to avoid a broken in-between state.
- **6 tests** (cross-midnight in, prior-day excluded, boundary-at-midnight excluded,
  forward-crosser in, and proof `watchForDay` still excludes the crosser).

### 2c. Phase 2 — row-based rendering (entries only) — ✅ COMPLETE
Rebuilt the Day View timeline body:
- `ListView.builder` of 24 variable-height rows (`_HourRow`). Segments lay
  left-to-right by minutes (`left = startMin/60*W`), width floored at **48px** and
  clamped inside the track; overlaps stack into lanes (`laneHeight = 52`), which
  make the row taller. Empty hours still render.
- **Provider swap decision:** `logEntriesForDayProvider` turned out to be shared by
  **4 consumers** (day_view, debrief, log_entry_sheet, carve_proposals), so instead
  of repointing it we added a **new `dayViewEntriesProvider`** (StreamProvider.family)
  calling `watchEntriesOverlappingDay`. The pie chart / `todayEntriesProvider` stay
  on `watchForDay`.
- Category color via a `{categoryId → category}` map →
  `Color(cat?.colorValue ?? 0xFF607D8B)` (there is **no** `entry.category` object,
  only `categoryId`).
- Removed the old `_hourPx = 76` stack and the `initState` scroll; replaced with a
  cumulative-height, post-frame, guarded `jumpTo` near the current hour.
- Kept swipe-to-delete (by **entry id**, so all of an entry's slices vanish
  together) and tap → `LogEntrySheet(existing:)`.
- **Bugs caught by the widget tests here:** (1) `GlassCard` was sizing to its label
  → segments rendered as tiny chips and taps landed on the `Dismissible`; fixed with
  `double.infinity` + `GlassCard.onTap`, plus a test asserting card size == segment
  size. (2) The new `Timer.periodic` makes `pumpAndSettle` never settle → tests use
  bounded pumps.
- Verified via a render-tree widget test (`day_view_row_layout_test.dart`) because
  the CC environment had **no Android device** this session (see §6).

### 2d. Now-line: vertical → horizontal — ✅ COMPLETE
Changed the current-time indicator from a full-height vertical line to a
**full-width horizontal line that slides down through the current hour's row**
(`top = minute/60 * rowHeight`), matching the old top-to-bottom time feel. Spans the
block area only (not the hour-number gutter), drawn last in the current row's Stack,
wrapped in `IgnorePointer`, with the end-of-hour clamp on the vertical axis so `:59`
stays inside the row. The 1-min ticker is unchanged. Device-confirmed.

### 2e. Phase 3a — routine overlay rebuilt for the rows — ✅ COMPLETE
Brought back the green/amber/red routine comparison as a per-row edge behind the
segments, via a pure planner + a thin widget:
- `lib/features/day_view/routine_overlay_planner.dart` — pure
  `planRoutineEdges(slots, logs, {day, now}) → List<HourRoutine?>` (length 24).
  `HourRoutine = (verdict, isPast, categoryId)`; `verdict ∈ {green, amber, red,
  neutral}`.
- **Verdict math (faithful rebuild from git `6d96084`):** coverage = **sum** of
  each log's overlapping minutes ÷ slot duration (**can exceed 1.0**, no
  `isUsageDerived` filtering). Category match = an overlapping log shares the slot's
  `categoryId` (**null == null counts as a match**, mirroring the old code).
  isPast = earlier day, or today with slot end ≤ now; future day = not past.
  Verdict: not past → neutral; past → green if coverage ≥ 0.75 **and** match, else
  amber if ≥ 0.10, else red. **16 tests.**
- **Applicable-slot filter** (same rule the Routine screen uses):
  `isActive == true && (dayOfWeek == date.weekday || dayOfWeek == 0)`
  (dayOfWeek 1–7 = Mon–Sun, 0 = every day). This is also the `isActive` filter.
- Widget draws the edge as the first Stack child (behind segments and now-line),
  reading the same `dayViewEntriesProvider` list the segments use.
- **Two render bugs caught by the follow-up widget tests** (neither showed in
  `flutter analyze` or the planner tests):
  1. `_routineEdge()` returned a `Positioned` wrapped in `IgnorePointer` inside the
     `Stack` → **illegal ParentData** (`Positioned` must be a direct Stack child).
     Fixed by moving `IgnorePointer` *inside* the `Positioned` (mirroring the
     now-line).
  2. The edge combined `borderRadius` with a **non-uniform** two-tone `Border`,
     which Flutter forbids. This is a **debug-only `assert`** — release builds strip
     it (so it shipped silently before), but `flutter test` **and `flutter run`
     (debug)** throw it, i.e. it *would* red-screen on the phone. Resolved with
     **Option A**: a rounded base block with a **uniform** faint border, plus the
     verdict accent as its **own left bar** layered on top (keys
     `routine_edge_$hour` and `routine_accent_$hour`).
- **10 overlay widget tests** (incl. #10: tapping a segment above an edge still
  opens the sheet). Device-verified working.

### 2f. Phase 3b — remove the LIVE badge — ✅ COMPLETE
- Deleted the `if (entry.isRealTime)` "LIVE" badge block from `_segment()`. No
  orphaned fields/imports.
- **`insertRealTime` was KEPT**, not deleted: the grep gate found it's used by two
  tests (`carve_logic_test.dart`, `insert_retroactive_test.dart`), so the "dead
  code" claim in the docs was wrong. The `isRealTime` column stays (no schema/
  migration change).

### 2g. Test + verification status
- **132 tests passing**, `flutter analyze` clean.
- New/changed files this session:
  `lib/features/day_view/hour_row_planner.dart` (+ test),
  `lib/features/day_view/routine_overlay_planner.dart` (+ test),
  `lib/core/database/daos/log_entries_dao.dart` (added `watchEntriesOverlappingDay`),
  `lib/providers/log_entries_provider.dart` (added `dayViewEntriesProvider`),
  `lib/features/day_view/day_view_screen.dart` (rebuilt timeline body, now-line,
  routine edge, LIVE badge removed),
  `test/overlap_day_query_test.dart`, `test/day_view_row_layout_test.dart`,
  `test/day_view_routine_overlay_test.dart`.

### 2h. Key lessons from this session (carry forward)
- **Widget/render-tree tests are load-bearing.** They caught **three** bugs that
  `flutter analyze` and the pure-function tests all missed — every one would have
  red-screened on the phone. Always add render-tree checks for widget wiring.
- **Debug-only asserts matter for dev.** `flutter run -d android` defaults to
  **debug**, so latent bugs release builds silently absorb (e.g. borderRadius on a
  non-uniform border) *will* surface on the developer's phone.
- The CC environment this session had **no Android device** (Windows/Chrome/Edge
  only; `supabase_flutter` / `flutter_secure_storage` / `connectivity_plus` have no
  desktop support), so verification = render-tree widget tests + the user's own
  phone eyeball.

---

## 3. Current state summary

| Area | State |
|---|---|
| Core logging, categories, sleep, visualizations | Built (prior sessions) |
| AI (Groq/Llama via Supabase proxy) | Built — **but debrief reported not working now** |
| Daily Intention → to-do list, swipe-delete, across-midnight fix | Built (chat 3) |
| Usage Stats over-counting | ✅ Fixed (chat 4) |
| Screen Time reconciliation rework (provenance, planCarve, schema 6→7) | Built (chat 5) |
| **Day View redesign (row layout, overlap query, now-line, routine overlay)** | ✅ **Complete & device-verified (this chat)** |
| LIVE badge | ✅ Removed (this chat) |
| Routine **page** (builder) still uses old chip layout | ❌ Needs redesign |
| Background gradient not updating by time of day | ❌ Broken (regression) |
| AI debrief | ❌ Reported not working |

---

## 4. Everything still to build / fix

Grouped by type. Items marked **(needs user detail)** can't be scoped until the
user specifies them.

### A. Broken now / bugs
1. **AI debrief not working** — was built (Groq/Llama via `groq-proxy`); now a
   regression. Diagnose where it fails (proxy? JWT/anon auth? quota 429? a client
   change? Supabase free-tier project paused?).
2. **Time-of-day background gradient not changing** — the dynamic background
   stopped updating; regression, needs diagnosis.
3. **Can't log into a previous day** — bug; **user to explain the exact behavior.**
   (needs user detail)
4. **Bottom navbar fix** — **user to specify what's wrong.** (needs user detail)
5. **AI-parse submit loop is unhardened** (from chat 5) — discards
   `insertRetroactive`'s return, pops unconditionally, no try/catch. **Silent
   data-loss risk** if ever enabled for usage-derived entries; harden before that.

### B. Features / enhancements
6. **Routine page redesign** — make the Routine builder use the same row-based,
   full-width, multi-hour-spanning layout as Day View. Right now a 4-hour "Study"
   slot only shows as a chip at its start hour (18:00). The data is correct (the
   Day View overlay spans all 4 hours). This screen is interactive (create/edit/
   delete slots, copy-to-days, day tabs, "+" button), so it needs its own
   diagnostic → spec → phased build. Some Day View row scaffolding may be reusable.
7. **Dashboard "right now" strip shows the current routine** — instead of just
   "right now — nothing logged," surface what the routine says for the current hour.
8. **Onboarding / first-run tour** — the core mental model (hour-just-ended,
   retroactive logging, sleep toggle). No API-key step.
9. **Supabase sync layer** — anonymous → permanent account, push local rows,
   multi-device (`user_id` already reserved on every table).

### C. UI / polish / cosmetic
10. **General UI fixes** — **user to enumerate which screens / what specifically.**
    (needs user detail)
11. **Screen Time card wording** — header still says "Screen Time Suggestions / tap
    Confirm to log detected screen time"; reword now that it also holds carves.
12. **Weekly-insight AI prompt** claims "actual vs planned" but is never actually
    sent the routine data (pre-existing bug).
13. **AI voice/persona consistency** across debrief, weekly insight, and category
    suggestion.
14. **App labeling / filtering robustness** in usage stats (app names). Also (from
    the chat-4 audit, reconfirm whether chat-5 fixed it): the Screen Time category
    may still be resolved by string name-match, which a rename would break.

### D. Screen Time reconciliation — narrower edges (from chat 5)
15. **Only one app can be reconciled per logged hour** — multi-app-per-hour,
    multi-hour, and mid-hour manual entries can't fully reconcile yet.
16. **11 PM–midnight hour never gets a suggestion/carve** — providers are today-only,
    capped at the current hour (deferred by user; the empty card 12–1 AM is correct,
    not a bug).

### E. Deferred / dropped by earlier decision (revivable)
17. **Screen Time "honesty layer" (Phase 3)** — AI coaching comparing logged vs.
    actual usage. Was the spec's headline idea, unblocked once the over-counting bug
    was fixed, but **dropped in chat 5**. Flagged so it isn't forgotten.

---

## 5. Working conventions (how this user likes to work)

Follow these — they were consistent and effective across every session:

- **Diagnose before fixing.** The first step for any fix/feature is a **read-only
  diagnostic** prompt that reads real code and reports (call-sites, schema,
  reactivity), changing nothing — so the build is against real code, not memory.
- **Ask permission before issuing any Claude Code prompt.** The user approves
  prompts before running them.
- **Spec-first / contract-first.** Lock the full behavioural spec (incl. edge
  cases) *before* code, and play it back for confirmation when dense.
- **Phased builds with verification gates.** Break work into phases; **STOP** at
  each gate, report, confirm before continuing. Include explicit verification
  checklists, and for regressions a test that provably fails-before / passes-after.
- **Prompts as complete pasteable markdown blocks** with a **STEP 0 read-only
  discovery** section, explicit **"Do NOT"** section, verification steps, and a
  **STOP-if-mismatch** gate before any write.
- **Pure-function-first for logic.** Put slicing/verdict logic in Flutter/Drift-free
  files with their own unit tests (`hour_row_planner.dart`,
  `routine_overlay_planner.dart`); keep the widget layer thin.
- **Add widget/render-tree tests for wiring**, since the CC env has no device — they
  catch what analyze + unit tests miss (they caught 3 red-screen bugs this session).
- **Modular; reuse existing patterns** rather than inventing parallel ones.
- **Reactivity discipline.** Missed-hours, Screen Time suggestions, task card/sheet,
  counts, and now the routine overlay are all Drift `.watch()` streams + Riverpod.
  Deletes/edits must flow through reactively. If something doesn't update, **find
  the non-reactive source and report it — don't paper over it with
  `provider.invalidate`** (a prior manual-invalidation fix once broke missed-hours).
- **Reply in simpler, plain language.** The user moves fast once trade-offs are
  clearly laid out.

---

## 6. Infrastructure & dev-environment notes (carried in)

- **Supabase:** Singapore region, anonymous auth. `ai_usage` table enforces the
  100 req/user/day quota server-side; RLS "users read own usage" (writes via Edge
  Function service_role). **Free tier pauses the project after ~1 week of
  inactivity — keep the dashboard active or expect AI downtime.** (Worth checking
  as a possible cause of the "AI debrief not working" report.)
- **Edge Function `groq-proxy`:** validates JWT, increments `ai_usage`, 429s over
  quota, forwards to Groq (`GROQ_API_KEY` from Supabase secrets), streams when
  `stream: true`.
- **Groq free tier** shared across users; cliff ~14,400 req/day total — monitor
  `ai_usage` as the user base grows.
- **Key rotation:** Groq key via `supabase secrets set GROQ_API_KEY=...` (no
  redeploy). Supabase anon key embedded in app (safe to expose; rotating needs an
  app update).
- **Dev environment (Windows + Android):** normally `flutter run -d android` with a
  **physical device + USB debugging**. Gotchas: delete stray `web/` folder (breaks
  sqlite3 FFI); keep the project on a short non-OneDrive path; Gradle
  `org.gradle.parallel=false`, `kotlin.incremental=false`; add Defender exclusions;
  bottom sheets need `useRootNavigator: true`.
- **`flutter run` is debug by default** — debug asserts are live, so latent
  "release-only-silent" bugs surface on the phone.
- **Test harness for DB-backed widget tests:** in-memory Drift DB
  (`NativeDatabase.memory()`), the sqlite3 DLL override at the top of `main()`,
  `db.getSettings()` to force `onCreate`, bounded pumps (because of the
  `Timer.periodic` now-line), and a careful teardown before `db.close()` (the close
  hangs while a Drift stream subscription is still unwinding).

---

## 7. Data-integrity note (carried in)

Because carves/suggestions write to the log on user confirmation, any carve
confirmed while the old Usage Stats bugs were live may have corrupted real hours.
Fixes correct future behaviour but don't repair already-written data — worth
auditing affected days by hand if anything looks off.
