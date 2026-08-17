# ChronoPlan — Session Handoff

A handoff document for a fresh chat to pick up ChronoPlan development with full context.
ChronoPlan is a **Flutter Android app** for hourly retrospective time-logging, routine
comparison, and AI-driven productivity coaching. This document covers: what was carried in
from prior chats, what this session built, current state, what's left, and working conventions.

---

## 1. Context carried in from previous chats

The user uploaded `ChronoPlan_1.md` (a living project spec) at the start of this session.
Key established facts from it and from prior work:

**Core concept**
- Tracks how the day is spent in hourly increments, compares against a user-defined ideal
  routine, and provides AI coaching on the gap. **The user — not the app — decides whether a
  day was good** (thumbs up/down; no app-generated verdict or score).
- Fundamental log model: at any moment past the top of an hour, the user logs *the hour that
  just ended*. No future logging. Missed hours surface as retroactive opportunities, never as
  "lateness."
- **Model pivot (prior session):** the old "real-time entries are sacred/immovable" concept was
  **removed**. Every entry is now an ordinary, fully-editable retrospective record. Nothing is
  immovable.

**Already built before this session**
- Time logging (hourly / custom-interval reminders, silent notifications, contextual quotes,
  missed-hours strip, free-text + one category tag per entry).
- Flexible categories (user-created, colour-coded, archivable; protected "Screen Time" system
  category; AI keyword auto-suggestion).
- Sleep mode (manual sun/moon toggle only; "still sleeping?" courtesy notification with no data
  side-effects; auto-detection removed).
- Routine builder & comparison (day-at-a-time vertical timeline, copy-to-days; green/amber/red
  ghost-block edges in Day View).
- Visualizations: daily pie (Dashboard), weekly stacked bar chart (History/Reports, fl_chart,
  Sun–Sat, week-view-only, trend summary row, drill-down by day).
- AI features via **Groq + Llama 3.1 8b Instant**, proxied through a Supabase Edge Function
  (`groq-proxy`), Supabase anonymous auth, 100 req/user/day quota. No user API key. Selectable
  coach persona (Drill Sergeant / Friendly Coach / Neutral Analyst). Graceful offline fallback.

**Tech stack**
- Flutter (Android first), Riverpod, Drift (SQLite, offline-first), Supabase (anon auth + Edge
  Functions + Postgres), flutter_local_notifications, fl_chart.
- Android usage: hand-rolled Kotlin `queryEvents` method channel (the `app_usage` package only
  returns daily aggregates, unusable for per-hour).

**UI direction**
- Glassmorphism, dark-mode-first. Semi-transparent `GlassCard`s with blur + rounded corners.
- Time-of-day dynamic background gradient. Manrope typography. Colourblind-aware category palette.
- Bottom nav: Dashboard | Day View | [+ Log] | Routine | History. `AppShell` hosts the nav as a
  persistent `ShellRoute`; full-page routes (e.g. `/debrief`) push on top of it.

**Known blocker carried in (still parked — NOT addressed this session)**
- **Usage Stats over-counting.** Per-hour usage is badly inflated (e.g. ~45h/day total, one app
  at ~20h). Root cause: foreground sessions aren't closed when the screen turns off — Android
  often doesn't emit `ACTIVITY_PAUSED` before sleep, so the last-open app stays "foreground"
  indefinitely and every subsequent hour re-attributes to it. The whole Usage Stats feature
  (and the Phase 3 "honesty layer") is parked behind this.

---

## 2. What this session built

### 2a. Swipe-to-delete on Day View log entries — ✅ COMPLETE

Added swipe-to-delete on Day View log-entry blocks, mirroring the Routine screen's existing
`Dismissible` (endToStart only, red background, no confirm).

- **Today-only:** past days render identical rows but `direction: DismissDirection.none`, so they
  don't swipe. Reuses the existing `_isToday` getter.
- **Stack adaptation:** Day View entries are `Positioned` children in a `Stack`, not `ListView`
  rows. Required `resizeDuration: null` and a synchronous `_pendingDeleteIds` guard set (add id in
  `onDismissed`, filter it out of the rendered list the same frame) to avoid the
  "dismissed Dismissible still part of the tree" assertion, since the actual data removal arrives
  async from the Drift stream. The set self-prunes when the stream re-emits without the id.
- **No regression:** missed-hours strip and Screen Time suggestions are both **reactive** off Drift
  streams, so deleting a log makes that hour read empty again and the chip/suggestion reappear on
  their own — no manual invalidation anywhere.

Files: `day_view_screen.dart` (`_entryBlock` ~L459, entry-mapping/filter site ~L117).

### 2b. Daily Intention → To-Do Expansion — ✅ COMPLETE

Replaced the single free-text "morning intention" with a per-day task list.

**Locked spec:**
- Morning "what would make today a win?" prompt is **removed entirely** as a stored field.
- Tasks belong to a **day** (`date` column), *not* to `daily_intentions` (no FK — Path 1).
- `daily_intentions` table is **kept only** as the home for `verdict_positive` (thumbs up/down);
  its `intention` text column is now vestigial. `setVerdict` already self-creates a placeholder
  row, so the debrief verdict path keeps working untouched.
- 5–10 tasks/day, insertion order.
- **Single flagged task** (flagging one clears any other — enforced in the DAO via transaction).
- **Two gestures:** swipe left (flutter_slidable, reveal-tray) shows **green "Done"** + **red
  "Remove"**.
  - **Done** → soft delete (`isDone=true`, `doneAt=now`); counts in debrief; hidden from sheet;
    does not carry over.
  - **Remove** → hard delete; no count; no carry-over. (No separate always-visible ✕ — Remove
    lives in the tray only.)
- **Dashboard card priority chain:** flagged task → else #1 task (lowest `sortOrder`, not done) →
  else empty prompt *"What's the one thing that would make today a win?"*
- **Carry-over:** implemented as a **roll-forward-on-load sweep** (not a midnight timer — no
  reliable background execution on Android). On day-load, any `isDone=false` task dated earlier
  than today has its `date` advanced to today, flag state preserved. Done/removed tasks never
  carry.

**Schema:** new `intention_tasks` table — `id`, `label` (note: named `label` not `text`, because
drift's analyzer collides on a column literally named `text`; public DAO param is still `text`),
`isDone`, `doneAt`, `isFlagged`, `sortOrder` (global monotonic, never reset per day), `date`
(midnight-normalized). **schemaVersion bumped 5 → 6**, migration mirrors the existing
`app_database.dart` pattern. Migration verified against a real v5 DB — no data loss.

**Debrief change:** AI context prompt now reads the flagged (or #1) task text + a
"completed X of Y tasks today" line, instead of the removed `intention.intention`. Verdict
read/write left completely untouched.

### 2c. Across-midnight task-disappearance fix — ✅ COMPLETE

A bug found in review (had slipped all four build gates): `dayTasksProvider` captured
`DateTime.now()` once at creation and wasn't day-keyed, while `rollForwardProvider` *was*. In a
**resident** app crossing midnight, rollForward would move tasks to the new day while the display
provider stayed bound to the old day → user's tasks appeared to vanish until a force-restart.
(Cold start worked, which is why it only bit intermittently.)

**Fix:**
- `dayTasksProvider` and `taskCountsProvider` converted to `.family` keyed by a normalized dayKey.
- New `currentDayProvider` (`StateProvider<DateTime>`) is the single source of "what day is it."
  Card, sheet, and debrief all **read it** for their dayKey instead of each calling
  `DateTime.now()` — closing the split-brain.
- `AppShell` (persistent shell host) converted to `ConsumerStatefulWidget` with a
  `WidgetsBindingObserver`; on `resumed`, if the real day changed, it flips `currentDayProvider`,
  switching every consumer to the new day's providers together.
- Regression test is **load-bearing** — verified to fail when the observer is disabled and pass
  when restored.

**Known edge (documented, not fixed):** the flip only fires on `resumed`. If the app is left in
the *foreground* untouched across midnight, the day won't roll until the next resume/cold start.
Negligible in practice; a next-midnight `Timer` reset on resume would close it if ever wanted.

**Verification:** 29 tests passing across the suite, `flutter analyze` clean.

---

## 3. Current state summary

| Area | State |
|---|---|
| Core logging, categories, sleep, routine, visualizations | Built (prior sessions) |
| AI (Groq/Llama via Supabase proxy) | Built (prior sessions) |
| Swipe-to-delete on Day View logs | ✅ Built this session |
| Daily Intention → to-do list | ✅ Built this session |
| Across-midnight provider fix | ✅ Built this session |
| Usage Stats accuracy | ❌ Parked — over-counting bug (biggest blocker) |
| Suggestion/manual-log overlap | ❌ Open — reconciliation attempt was reverted |

---

## 4. Still to build (backlog)

Ordered by rough impact:

1. **Usage Stats over-counting bug (HIGH — the real blocker).** Reconstruct one full-day
   foreground timeline from `queryEvents`, then slice into hour buckets. Close each session at the
   *earliest* of: next `ACTIVITY_PAUSED`/`MOVE_TO_BACKGROUND` for that package, next
   `ACTIVITY_RESUMED` for a *different* package, a screen-off / `SCREEN_NON_INTERACTIVE` event, a
   keyguard/lock event, `DEVICE_SHUTDOWN`, or timeline end. **Do not** close on `ACTIVITY_STOPPED`
   alone. Hard invariants: no session or per-app-per-hour total exceeds the bucket; sessions never
   overlap; no negative/zero durations. A raw-events + reconstructed-sessions debug view already
   exists — diagnose against real timestamps, don't guess from the summary card. Unblocks the
   Phase 3 "honesty layer."

2. **Suggestion/manual-log overlap (MEDIUM — open).** Accepting a Screen Time suggestion then
   manually logging the same hour produces overlapping entries. A prior attempt at a full
   reconciliation rewrite **broke working features (missed-hours suggestions) and didn't fix the
   overlap — it was reverted.** Approach the retry much more tightly scoped. Suspected root cause:
   multiple independent write paths (manual submit, suggestion accept, carve confirm) don't share
   one reconciling insert; possibly an inclusive/exclusive boundary bug at the top of the hour.

3. **Onboarding flow (LOW risk, self-contained).** First-launch tour of the core mental model
   (hour-just-ended, retroactive logging, sleep toggle). No API-key step needed.

4. **Routine Builder UI polish.** User to enumerate specific rough edges before this is actionable.

5. **Day View overlay refinement.** Verify green/amber/red edge logic against real use.

6. **Supabase sync layer (full).** Anonymous → permanent account upgrade, push local rows,
   multi-device sync. `user_id` already reserved on every table.

7. **AI polish.** Persona consistency across debrief / weekly insight / category suggestion;
   consider a stronger model for the debrief specifically (proxy makes provider swap near-trivial).

8. **Usage Stats Phase 3 — "honesty layer"** (AI coaching on logged-vs-actual discrepancies).
   *Blocked on #1.*

---

## 5. Data-integrity note (carried in)

Because carves/suggestions write to the log on user confirmation, any carve confirmed while the
Usage Stats bugs were live may have corrupted real hours (e.g. a full slot converted to Screen
Time). Worth auditing affected days by hand; fixes correct future behaviour but don't repair
already-written data.

---

## 6. Working conventions (how this user likes to work)

These were consistent and effective across the session — a new chat should follow them:

- **Diagnose before fixing.** Never make blind changes. Before any build, run a **read-only
  diagnostic prompt** (changes nothing, reports call-sites/schema/reactivity) so the fix is built
  against real code, not assumptions.
- **Ask permission before issuing any Claude Code prompt.** The user explicitly wants to approve
  prompts before running them.
- **Spec-first / contract-first.** Lock the full behavioural spec (including edge cases) *before*
  writing code. Play the spec back for confirmation when it's dense.
- **Phased builds with verification gates.** Break work into phases; STOP at each gate, report,
  and confirm before continuing. Include explicit verification checklists (and, for regression
  fixes, a test that provably fails-before / passes-after).
- **Prompts as complete pasteable markdown blocks** with explicit "Do NOT" sections and
  verification steps.
- **Modular architecture; reuse existing patterns** rather than inventing parallel ones (e.g. the
  task sheet reuses the log-entry sheet's `GlassCard` + `showModalBottomSheet(useRootNavigator:
  true)` chrome; swipe mirrors Routine's `Dismissible`).
- The user moves fast once trade-offs are clearly laid out.

**Reactivity discipline (important):** missed-hours, Screen Time suggestions, task card/sheet, and
counts are all backed by Drift `.watch()` streams + Riverpod. Deletes/edits must flow through
reactively. If something doesn't update, **find the non-reactive source and report it — don't
paper over it with `provider.invalidate`.** (A prior manual-invalidation-style fix is what broke
the missed-hours feature.)

---

## 7. Infrastructure notes (carried in)

- **Supabase:** Singapore region, anonymous auth. `ai_usage` table enforces the 100 req/user/day
  quota server-side; RLS "users read own usage" (writes via Edge Function service_role). **Free
  tier pauses the project after ~1 week of inactivity — keep the dashboard active or expect AI
  downtime.**
- **Edge Function `groq-proxy`:** validates JWT, increments `ai_usage`, 429s over quota, forwards
  to Groq (`GROQ_API_KEY` from Supabase secrets), streams when `stream: true`.
- **Groq free tier** shared across users; cliff ~14,400 req/day total — monitor `ai_usage` as the
  user base grows.
- **Key rotation:** Groq key via `supabase secrets set GROQ_API_KEY=...` (no redeploy). Supabase
  anon key embedded in app (safe to expose; rotating needs an app update).

**Dev environment (Windows + Android):** always `flutter run -d android` with a physical device +
USB debugging. Known gotchas: delete stray `web/` folder (breaks sqlite3 FFI); keep project on a
short non-OneDrive path; Gradle set `org.gradle.parallel=false`, `kotlin.incremental=false`; add
Defender exclusions. Bottom sheets need `useRootNavigator: true`.
