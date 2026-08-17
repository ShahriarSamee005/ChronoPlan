# ChronoPlan — Session Handoff (Chat 4)

A handoff document for a fresh chat to pick up ChronoPlan development with full context.
ChronoPlan is a **Flutter Android app** for hourly retrospective time-logging, routine
comparison, and AI-driven productivity coaching. This is the 4th chat in the project's history
(prior handoffs: `ChronoPlan_1.md`, `ChronoPlan_2.md`, `ChronoPlan_3.md`). This document covers:
the app context carried in, what this session did (the big one: the Usage Stats over-counting
blocker is **fixed**), a mid-session correction worth flagging loudly, current state, what's
left, and the working conventions to keep following.

---

## 1. App context (carried in — stable)

**Core concept**
- Tracks how the day is spent in hourly increments, compares against a user-defined ideal
  routine, and provides AI coaching on the gap. **The user — not the app — decides whether a day
  was good** (thumbs up/down; no app-generated verdict or score).
- Log model: at any moment past the top of an hour, the user logs *the hour that just ended*. No
  future logging. Missed hours surface as retroactive opportunities, never as "lateness."
- **No "sacred" entries** (pivot from an earlier model): every entry is an ordinary,
  fully-editable retrospective record. Nothing is immovable.

**Built in prior sessions**
- Time logging (hourly / custom-interval reminders, silent notifications, contextual quotes,
  missed-hours strip, free-text + one category tag per entry).
- Flexible categories (user-created, colour-coded, archivable; protected **"Screen Time"** system
  category; AI keyword auto-suggestion).
- Sleep mode (manual sun/moon toggle only; "still sleeping?" courtesy notification with no data
  side-effects; auto-detection removed).
- Routine builder & comparison (day-at-a-time vertical timeline, copy-to-days; green/amber/red
  ghost-block edges in Day View).
- Visualizations: daily pie (Dashboard, by category from **logged entries**), weekly stacked bar
  chart (History/Reports, fl_chart, Sun–Sat, week-view-only, trend row, drill-down by day).
- AI via **Groq + Llama 3.1 8b Instant**, proxied through a Supabase Edge Function (`groq-proxy`),
  Supabase anonymous auth, 100 req/user/day quota, no user API key, selectable coach persona
  (Drill Sergeant / Friendly Coach / Neutral Analyst), graceful offline fallback.
- Daily Intention → per-day to-do list (built in chat 3: `intention_tasks` table, schemaVersion
  5→6, roll-forward carry-over, single flagged task, done=soft-delete / remove=hard-delete).
- Swipe-to-delete on Day View log entries; across-midnight provider fix (`currentDayProvider` +
  `AppShell` `WidgetsBindingObserver` day-flip on resume).

**The Usage Stats / "Screen Time" feature — what it actually is** (the spec's most distinctive
feature; built across chats 1–2 as Phases 1 / 2a / 2b):
- **Phase 1** — `PACKAGE_USAGE_STATS` permission (value-prop card gated on `appOpenCount >= 2`),
  the protected **Screen Time** category, the usage service, a raw-events + reconstructed-sessions
  debug view.
- **Phase 2a — Suggestions (empty hours):** an *empty* hour with detected app usage (today-only,
  ≥10 min) surfaces a **"Screen Time Suggestions"** card → user **confirms + categorizes** (default
  Screen Time, asks every time) or dismisses. Confirm writes a log entry for that hour.
- **Phase 2b — Carves (logged hours):** a *logged* hour with detected usage proposes a
  user-confirmed carve-out — the detected app's time splits out of the entry into its own Screen
  Time entry, shown **side-by-side in the Day View row** ("Learning 47m | YouTube 13m"), totals
  summing to the hour, nothing overlapping. Auto-suppressed when the app name is already in the
  log text. ≥10 min threshold.
- Confirmed entries flow into the **daily pie** (Screen Time category) and sit **beside logged
  work in Day View** automatically, because they are ordinary log rows written through the same
  DAO as manual logging.
- **Phase 3 (NOT built):** AI coaching that cross-references logged hours against actual usage and
  surfaces discrepancies non-judgmentally. This was blocked purely on trustworthy usage numbers —
  which this session unblocked.

**Tech stack**
- Flutter (Android first), Riverpod, Drift (SQLite, offline-first), Supabase (anon auth + Edge
  Functions + Postgres), flutter_local_notifications, fl_chart.
- Android usage: hand-rolled Kotlin `queryEvents` method channel (the `app_usage` /
  `queryUsageStats` route only returns daily aggregates, unusable for per-hour).

**UI direction**
- Glassmorphism, dark-mode-first. Semi-transparent `GlassCard`s with blur + rounded corners.
  Time-of-day dynamic background gradient. Manrope typography. Colourblind-aware category palette.
- Bottom nav: Dashboard | Day View | [+ Log] | Routine | History. `AppShell` hosts the nav as a
  persistent `ShellRoute`; full-page routes push on top of it.

---

## 2. What this session (chat 4) did

### 2a. Usage Stats over-counting bug — ✅ FIXED (was the #1 blocker)

This was the parked blocker behind the whole Screen Time / honesty-layer feature (per prior
handoffs: ~45h/day totals, one app at ~20h). It is now fixed at the reconstruction level and
unit-proven.

**Real root cause (found by read-only diagnosis — corrected two wrong prior theories):**
- The prior handoffs blamed "sessions aren't closed when the screen turns off." **Wrong** — those
  close paths exist and fire.
- An early theory this session (a package filter dropping screen-off signals) was also **wrong** —
  no such filter exists.
- **Actual cause:** an "assumed-open-since-start" branch in `usage_stats_service.dart` (~L238)
  back-dated *any* lone unmatched `BACKGROUND` to midnight (`windowStart`), because `openPkg` was
  reset to `null` after *every* close (screen-off / keyguard / shutdown / matched-BG), which
  happens dozens of times a day. Any stray mid-day background then manufactured a session up to
  ~20h long; several overlapped with no cap → ~45h/day. Query windowing (one full-day
  `queryEvents` call, sliced in Dart) and hour bucketing were both already correct.

**The fix landed in two gated stages (internal labels "Phase A" and "Phase B" — my naming, not
project phases):**

- **"Phase A" — bound the back-dating + guards.** Deleted the `assumedOpenAtStart` back-date. A
  lone unmatched `BACKGROUND` now resolves by priority:
  1. **Screen-on watermark** — credit `[max(screenOnSince, lastEnd), BG]` if the screen was
     provably on leading in (`max(..., lastEnd)` prevents overlapping an already-emitted session).
  2. **Head case** — `[windowStart, BG]` *only* if it's genuinely the first session-affecting
     event of the day (true open-across-midnight), capped at **90 min**.
  3. Otherwise **drop**.
  Added event types **15 (`SCREEN_INTERACTIVE`)** and **18 (`KEYGUARD_HIDDEN`)** to the Kotlin
  filter as the watermark signals (API 28+; on API 24–27 no watermark exists, so it degrades to
  drop). Added **invariant guards**: per-(hour, package) and per-hour-total ≤ 60 min, which clamp
  in release and surface as a red **"GUARD TRIPPED"** section in the debug view (`getHourlyUsage`
  public signature unchanged — violations threaded via an optional out-param).

- **"Phase B" — suspend/resume mask (interior-wake accuracy).** Screen-off (16/17) now
  **suspends** an anchored session (emits the active segment, keeps `openPkg`) instead of closing
  it; screen-on (15/18) **resumes** it; matched BG / a different app's FOREGROUND /
  `DEVICE_SHUTDOWN`(26) / timeline-end **close** it; a session still suspended at timeline-end
  contributes nothing. An anchored multi-wake session now emits one contiguous sub-session per
  screen-on segment, so `_sliceByHour` is unchanged. This recovers interior on-screen wakes that
  Phase A dropped (e.g. a stream Phase A scored at 15 min is now the correct 20 min). The
  unanchored lone-BG watermark/head/drop ladder is untouched.
  - **Modelling point worth keeping:** after a mid-day `DEVICE_SHUTDOWN` fully closes a session, a
    reappearing foreground app IS still credited via the normal post-boot lone-BG watermark (real,
    bounded, screen-on usage — not a phantom). We deliberately chose to keep it rather than add a
    post-shutdown quarantine, because quarantining would under-count real reboot-day usage.

**Testing & discipline.** `test/usage_phantom_background_test.dart` is the acceptance spec,
written **failing-first** each stage (fail-before / pass-after). The five original phantom numbers
(1198 / 1290 / 720 / 635 / 680 min) became the correct values (0 / 45 / 0 / 0 / 35). Full suite is
**green (47 tests at last run)**, `flutter analyze` clean. Every fix followed a read-only
diagnostic first.

**Verification limitation (open, minor):** retro-verification against an *old* over-counted day is
not possible via the UI — the Usage debug view shows **today only**, no previous-day picker. So
the fix is **unit-proven + clean-boot-verified on device**; today's usage accrues correctly going
forward. (Historical days already written with corrupted carves are not repaired — see §5.)

### 2b. Dashboard launch crash — ✅ FIXED

The app threw on cold start:
`dependOnInheritedWidgetOfExactType<UncontrolledProviderScope>() ... called before
_DashboardScreenState.initState() completed.`

- **Cause (pure timing bug):** `initState` synchronously called `_onResume`, which calls
  `ref.invalidate` on three providers; `ref.invalidate` resolves Riverpod's `late _container` via
  `dependOnInheritedWidgetOfExactType`, which Flutter forbids until `initState` returns. (`ref.read`
  at the top of the method survived only because it uses the `listen:false` path.) The three
  invalidates (`usagePermissionProvider` / `todayUsageProvider` / `hourlyUsageForTodayProvider`)
  are **load-bearing** — one-shot `FutureProvider`s over Android platform channels with no Drift
  stream behind them, so nothing refreshes them on its own. Not related to the across-midnight /
  `AppShell` handler (disjoint). Detonator was the earlier "screen time added" commit adding the
  invalidates to a method that had run synchronously in `initState` (harmlessly, `ref.read` only)
  since v1.
- **Fix:** defer the cold-start priming call out of `initState` into
  `WidgetsBinding.instance.addPostFrameCallback` (the idiom `day_view_screen.dart` and
  `routine_screen.dart` already use), keeping the `didChangeAppLifecycleState(resumed)` wiring and
  all three invalidates as-is (can't just delete the initState call — Flutter delivers no
  `resumed` on first launch, so cold start would lose the usage refresh). Added a regression widget
  test. App now boots clean to the dashboard.

### 2c. Screen Time feature — clarified and audited (no code change)

Substantial confusion was resolved this session. A read-only audit confirmed the
**confirm → log → pie → Day-View honesty flow is fully built and wired end-to-end**:
- `/screen-time` has **three** cards: `UsageAccessCard` (permission), **`_TodayUsageCard`** (the
  passive top-8 per-app list — informational only, no actions), and **`UsageSuggestionsCard`**
  (the Phase 2a confirm/dismiss control with per-hour category chips).
- Phase 2b carves render side-by-side (58/42 flex) in the Day View timeline whenever a proposal
  matches an entry id.
- Both write ordinary Screen Time-category log rows via the same `insertRetroactive` DAO manual
  logging uses; the pie reads `todayEntriesProvider` + `categoriesProvider` grouped by
  `categoryId`, so a confirmed entry appears in pie + Day View with zero extra wiring.

The user's report that "the Screen Time card only shows a passive top-8 list with no confirm
button" was because they were looking at `_TodayUsageCard` (which is deliberately passive) while
the `UsageSuggestionsCard` below it was **legitimately empty at that moment** (see §2d).

### 2d. Midnight blind-spot — identified, deferred by user

The Suggestions card looked empty during 12–1 AM because the suggestion/carve providers are
**today-only and cap the scan at `now.hour`** — right after midnight `now.hour == 0`, so there are
zero elapsed today-hours to scan (correct, not a bug). The structural consequence: **the
11 PM–midnight hour can never get a usage suggestion/carve** — too-late-today going in,
too-early-yesterday coming out. Closing it later = let the suggestion/carve window reach back to
"the hour that just ended" even when it belongs to late yesterday (a scoped provider-window
change, not a rewrite). **User chose to defer this to a later iteration.**

---

## ⚠️ 2e. IMPORTANT CORRECTION — do not build the invented "Phase C"

During this session I (the assistant) proposed a **"Phase C" that folds unattributed screen-on
time into a generic Screen Time bucket** (`unattributed = total screen-on − Σ attributed`). **This
was a misread of the product and has been retracted.** There is **no** "screen-on total /
anonymous unattributed bucket" concept in ChronoPlan. The real Screen Time feature is the
confirm-into-log honesty flow described in §1. A new chat should **not** build the unattributed
bucket. (The "Phase A"/"Phase B" labels above *were* real work — the reconstruction fix — and are
done; only "Phase C" was fictional.)

---

## 3. Current state summary

| Area | State |
|---|---|
| Core logging, categories, sleep, routine, visualizations | Built (prior sessions) |
| AI (Groq/Llama via Supabase proxy) | Built (prior sessions) |
| Daily Intention → to-do list, swipe-delete, across-midnight fix | Built (chat 3) |
| Screen Time confirm → log → pie → Day-View flow (Phases 1/2a/2b) | ✅ Built & wired (verified by audit this session) |
| **Usage Stats over-counting** | ✅ **FIXED this session** (reconstruction; unit-proven + clean boot) |
| Dashboard launch crash | ✅ Fixed this session |
| Screen Time **Phase 3** (AI honesty coaching) | ❌ Not built — now UNBLOCKED |
| Suggestion/manual-log overlap | ❌ Open (prior full rewrite reverted) |
| Midnight (11 PM–12 AM) suggestion gap | ❌ Open — deferred by user |

---

## 4. Still to build (backlog, updated)

Roughly by impact:

1. **Screen Time Phase 3 — the honesty layer proper.** AI coaching that cross-references logged
   hours vs. actual usage and surfaces discrepancies non-judgmentally through the coach. The
   spec's headline feature; was blocked only on trustworthy usage numbers, which now exist. The
   most substantive remaining work.
2. **Suggestion/manual-log overlap bug.** Accept a Screen Time suggestion for an hour, then
   manually log that hour → overlapping entries; the "entries never overlap" invariant isn't
   enforced across a suggestion-created entry and a subsequent manual entry. The manual-log path
   must reconcile against suggestion-created entries in the same bucket. **A prior FULL
   reconciliation rewrite was reverted for breaking the missed-hours feature — retry must be
   tightly scoped.**
3. **Screen Time discoverability / robustness gaps** (found in the audit, all small):
   - No pending-suggestion **badge/count** on the Dashboard `_ScreenTimeCard` — the confirm flow
     is easy to miss (this is essentially what confused the user this session).
   - The carve UI **silently vanishes on entries under ~50px tall** (`if (height < 50) return
     _entryBlock(entry);`) — short logged hours never show their carve affordance.
   - Both confirm paths resolve the Screen Time category by **string name-match**
     (`c.name == 'Screen Time'`); a category rename would break the default selection. Replace with
     a single shared resolver (stable id/`isSystem` check).
   - Usage-confirmed entries are **schema-indistinguishable** from hand-typed retroactive ones (no
     provenance flag) — forecloses a future "confirmed vs. logged" view. Consider a provenance
     column if that view is ever wanted.
   - Stale doc comment: `usage_stats_provider` still says "Expensive (24 separate OS queries)" —
     it's now one full-day call.
4. **Midnight (11 PM–midnight) suggestion gap** (§2d) — deferred by user.
5. **Onboarding flow** (first-launch tour of the mental model; no API-key step).
6. **Routine Builder UI polish** (user to enumerate rough edges).
7. **Day View overlay refinement** (verify green/amber/red edge logic against real use).
8. **Supabase sync layer** (anonymous → permanent account, push local rows, multi-device;
   `user_id` already reserved on every table).
9. **AI polish** (persona consistency across debrief / weekly insight / category suggestion;
   consider a stronger model for the debrief).
10. **App labeling / filtering robustness** (resolve labels via `PackageManager`, filter
    no-launcher-intent packages; any per-entry failure must degrade **per-entry**, never wipe the
    whole list — a prior filter once over-filtered to an empty list).

**Optional test hardening (noted, not urgent):** the current shutdown test can't distinguish
"shutdown-closes" from "shutdown-suspends" (byte-identical spans on that stream) — pinning it needs
a stream with a *different* app's event after the shutdown.

---

## 5. Data-integrity note (carried in)

Because carves/suggestions write to the log on user confirmation, any carve confirmed while the
over-counting bug was live may have corrupted real hours (e.g. a full slot converted to Screen
Time). The over-counting *fix* corrects future reconstruction, but does **not** repair
already-written log rows. Worth a hand-audit of affected days if the user notices bad historical
data.

---

## 6. Working conventions (how this user likes to work — keep following)

- **Diagnose before fixing.** Never make blind changes. Run a **read-only diagnostic prompt** first
  (changes nothing; reports call-sites / schema / reactivity against real code). This session's
  diagnostics repeatedly overturned wrong assumptions — it's load-bearing, not ceremony.
- **Ask permission before issuing any Claude Code prompt.** The user approves prompts before they
  run.
- **Spec-first / contract-first.** Lock the full behavioural spec (incl. edge cases) before code;
  play it back for confirmation when dense.
- **Phased builds with verification gates.** Break work into phases; STOP at each gate, report, and
  confirm. Include explicit verification checklists, and for regression fixes a test that provably
  **fails-before / passes-after** (and verify the test is non-vacuous by reintroducing the bug).
- **Prompts as complete pasteable markdown blocks** with explicit "Do NOT" sections and
  verification steps.
- **Modular architecture; reuse existing patterns** rather than inventing parallel ones.
- **Reactivity discipline:** missed-hours, Screen Time suggestions, task card/sheet, and counts are
  Drift `.watch()` streams + Riverpod. Deletes/edits must flow through reactively. If something
  doesn't update, **find the non-reactive source and report it — don't paper over it with
  `provider.invalidate`.** (A prior manual-invalidation fix is what broke the missed-hours feature.)
  Note: the *usage* providers are the deliberate exception — they're one-shot `FutureProvider`s over
  platform channels and are correctly invalidated on resume.
- The user moves fast once trade-offs are clearly laid out.

---

## 7. Infrastructure notes (carried in)

- **Supabase:** Singapore region, anonymous auth. `ai_usage` table enforces the 100 req/user/day
  quota server-side; RLS "users read own usage" (writes via Edge Function service_role). **Free
  tier pauses the project after ~1 week of inactivity — keep the dashboard active or expect AI
  downtime.** (Supabase host-lookup warnings in `flutter run` logs are just the paused/offline
  project — expected, non-fatal.)
- **Edge Function `groq-proxy`:** validates JWT, increments `ai_usage`, 429s over quota, forwards
  to Groq (`GROQ_API_KEY` from Supabase secrets), streams when `stream: true`.
- **Groq free tier** shared across users; cliff ~14,400 req/day total — monitor `ai_usage` as the
  user base grows.
- **Key rotation:** Groq key via `supabase secrets set GROQ_API_KEY=...` (no redeploy). Supabase
  anon key embedded in app (safe to expose; rotating needs an app update).

**Dev environment (Windows + Android):** always `flutter run -d android` with a physical device +
USB debugging (test device this session: RMX3521). Known gotchas: delete stray `web/` folder
(breaks sqlite3 FFI); keep project on a short non-OneDrive path; Gradle
`org.gradle.parallel=false`, `kotlin.incremental=false`; add Defender exclusions. Bottom sheets
need `useRootNavigator: true`.

**Usage debug view reachability:** Dashboard → tap the Screen Time card → **long-press the
"Screen Time" AppBar title** → `/debug-usage`. (The *dashboard* title is `onTap → /about` only; it
has no debug gesture.) The debug view shows **today only** (no previous-day picker).

---

## 8. Key file map (Usage Stats / Screen Time subsystem)

- `lib/core/usage_stats/usage_stats_service.dart` — `AppUsageEntry`, `_reconstructSessions`
  (the session state machine — where the over-counting fix lives), `_sliceByHour`,
  `_enforceHourGuards`, the `@visibleForTesting` seams (`reconstructSessionsForTest`,
  `sliceByHourForTest`), `getHourlyUsage`, `getTodayUsage` (note: bypasses `_sliceByHour`, sums
  sessions directly), `getDebugSnapshot`.
- `android/app/src/main/kotlin/.../MainActivity.kt` — `queryEvents` method channel; emits event
  types 1, 2, 15, 16, 17, 18, 26.
- `lib/providers/usage_stats_provider.dart` — `usagePermissionProvider`, `todayUsageProvider`,
  `hourlyUsageForTodayProvider` (one-shot FutureProviders; invalidated on resume).
- `lib/providers/usage_suggestions_provider.dart` + `lib/features/dashboard/widgets/usage_suggestions_card.dart`
  — Phase 2a (empty-hour suggestions; mounted on `/screen-time`, **not** the Dashboard despite the
  folder).
- `lib/providers/carve_proposals_provider.dart` + `lib/features/day_view/widgets/entry_with_carves.dart`
  — Phase 2b (logged-hour carves; rendered in Day View timeline).
- `lib/features/screen_time/screen_time_screen.dart` — the 3-card screen (`UsageAccessCard`,
  `_TodayUsageCard`, `UsageSuggestionsCard`).
- `lib/features/dashboard/widgets/daily_pie_chart_card.dart` — pie (logged entries by category).
- `lib/core/database/daos/log_entries_dao.dart` — `insertRetroactive` (shared write path for
  manual logs, suggestions, and carves).
- `test/usage_phantom_background_test.dart` — the over-counting acceptance spec.
