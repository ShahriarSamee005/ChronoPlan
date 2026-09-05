# ChronoPlan — Session 7 Handoff

A handoff document for a fresh chat to pick up ChronoPlan development with full context.
ChronoPlan is a **Flutter Android app** for hourly retrospective time-logging, routine
comparison, and AI-driven productivity coaching. This document covers: what the app is,
what was carried in, what THIS session built/fixed, current state, what's left, and the
working conventions the user expects.

---

## 1. What ChronoPlan is (core concept)

- Tracks how the day is spent in **hourly increments**, compares it against a user-defined
  **ideal routine**, and provides **AI coaching** on the gap. **The user — not the app —
  decides whether a day was good** (thumbs up/down; no app-generated score).
- **Log model:** at any moment past the top of an hour, the user logs *the hour that just
  ended*. **No future logging.** Missed hours surface as retroactive opportunities, never as
  "lateness." Every entry is an ordinary, fully-editable retrospective record — nothing is
  immovable.

**Tech stack**
- Flutter (Android first), Riverpod, Drift (SQLite, offline-first), Supabase (anonymous
  auth + Edge Functions + Postgres), flutter_local_notifications, fl_chart, flutter_slidable,
  go_router.
- Android per-hour usage: hand-rolled Kotlin `queryEvents` method channel (the `app_usage`
  package only gives daily aggregates).
- **AI** via **Groq**, proxied through a Supabase Edge Function (`groq-proxy`) with anonymous
  auth and a 100 req/user/day quota. No user API key. Selectable coach persona (Drill
  Sergeant / Friendly Coach / Neutral Analyst). Graceful offline fallback.
- **AI model as of this session: `openai/gpt-oss-20b`** (changed from the now-retired
  `llama-3.1-8b-instant` — see §3.2). Model name is a single `const` in
  `lib/config/supabase_config.dart`.

**UI direction**
- Glassmorphism, dark-mode-first. Semi-transparent `GlassCard`s with blur + rounded corners.
- Time-of-day dynamic background gradient. Manrope typography. Colourblind-aware category
  palette.
- Bottom nav: Home (Dashboard) | Day | [+ Log] | Routine | History. `AppShell` hosts the nav
  as a persistent `ShellRoute`; full-page routes (e.g. `/debrief`) push on top.

**Already built before this session** (from chats 1–6)
- Time logging (hourly / custom-interval reminders, silent notifications, contextual quotes,
  missed-hours strip, free-text + one category tag per entry).
- Flexible categories (user-created, colour-coded, archivable; protected "Screen Time" system
  category; AI keyword auto-suggestion).
- Sleep mode (manual sun/moon toggle; courtesy "still sleeping?" notification, no data side
  effects).
- Routine builder & comparison (day tabs, copy-to-days; green/amber/red routine overlay edges
  in Day View).
- Visualizations: daily pie (Dashboard), weekly stacked bar chart (History).
- Daily Intention → per-day to-do list (flagged task, swipe done/remove, roll-forward carry-over).
- Day View **row-layout redesign** (per-hour rows, cross-midnight query, now-line, routine
  overlay) — device-verified in chat 6.
- Usage Stats over-counting fix (chat 4) and Screen Time reconciliation rework (chat 5).
- AI: debrief (SSE streaming), weekly insight, parse-from-text, category suggestion.

---

## 2. What was planned at the start of this session

The user's opening intent: **finish what's left** on the backlog inherited from chat 6.
Open items at session start, grouped:
- **Broken-now:** AI features not working; time-of-day gradient not changing; can't log a
  previous day; a bottom-navbar issue; AI-parse submit loop unhardened.
- **Features:** Routine page redesign (row layout); Dashboard "right now" routine strip;
  onboarding tour; Supabase sync layer.
- **Polish:** Screen Time card wording; weekly-insight prompt missing routine data; AI persona
  consistency; app-name labeling robustness.
- **Narrow Screen Time edges:** only one app reconciled per hour; the 11 PM–midnight gap.
- **Deferred/dropped:** Screen Time "honesty layer."

We worked, in order: Routine redesign → AI outage → gradient → past-day logging.

---

## 3. What THIS session built / fixed

### 3.1 Routine page redesign (row layout) — ✅ DONE (device eyeball on Routine still owed)

Goal locked with the user: **visual consistency** — make the Routine screen use the same
row-based look as the new Day View. A read-only diagnostic **overturned the stated premise**
(multi-hour slots were said to render as a single chip; the code already spanned them as a
full-height block). Real goal became pure visual consistency, not a bug fix.

Approach: **Path 1 — extract a shared widget** (chosen over a parallel copy so the two screens
can't visually drift).

- **Phase A — new shared `HourTimeline`.** Extracted Day View's private row/segment timeline
  into a reusable stateless widget at **`lib/core/theme/hour_timeline.dart`** (next to
  `GlassCard`). It owns the 24-row `ListView`, hour gutter + labels, segment geometry
  (`_laneHeight=52`, `_minSegWidth=48`, `_gutterWidth=52`, radius 8), corner rounding, the
  `Dismissible` swipe, and `GlassCard.onTap`. Callers pass `rows`, `scrollController`,
  `segmentColor`, `segmentLabel`, `onSegmentTap`, `onSegmentDelete`, `swipeEnabled`,
  `onEmptyHourTap?`, `backgroundLayers?` (routine edge), `foregroundLayers?` (now-line).
  Day View rewired onto it with **byte-identical keys** so its render tests pass unmodified.
  Day View device-verified identical.
- **Phase B — Routine screen rebuilt on `HourTimeline`.** New pure adapter
  **`lib/features/routine/routine_plan_adapter.dart`** (`slotsToPlanEntries(...)`) maps
  hour-based slots (`startHour` + `durationHours`) into the planner's `PlanEntry` input via a
  thin hour→DateTime shim; the planner is untouched. Every gesture preserved (tap-empty →
  create, tap slot → edit, swipe → delete, day tabs, copy-to-days). Added a `_pendingDeleteIds`
  guard mirroring Day View.
- **STEP 0 caught two prompt errors** (both resolved to preserve current behaviour): slots
  **do** have a free-text `label` (segment label = `label` → category name → "Unlabelled"); the
  Routine day-filter is **dayOfWeek-only** (no `isActive` check).
- **Accepted visual change (user's call):** the old "every-day slot" treatment (dimmed opacity
  + "Every day" caption) is gone, since `HourTimeline`'s chrome is fixed. Trade-off: on a day
  tab you can't tell an every-day slot from a day-specific one, and deleting an every-day slot
  removes it from all 7 days with no cue. User chose to leave the cue out.

### 3.2 All AI features broken — ✅ FIXED (confirmed working)

Symptom: every AI feature (parse, debrief, weekly insight, category suggestion) failed at once
with the generic "couldn't reach AI" fallback. Because all AI shares one path (Supabase anon
auth → `groq-proxy` → Groq), an all-at-once failure = shared backend, not app logic. It turned
out to be **a chain of three separate backend problems**, fixed in order:

1. **Supabase project auto-paused** (free tier pauses after ~1 week idle). → User resumed it in
   the dashboard.
2. **Groq API key expired/revoked** (`401 invalid_api_key` / `expired_api_key`). → User created
   a new key in the Groq console and updated the `GROQ_API_KEY` secret.
3. **Model `llama-3.1-8b-instant` retired by Groq** (Groq announced its deprecation on
   2026-06-17; now returns `404 model_not_found`). → Swapped to **`openai/gpt-oss-20b`**
   (Groq's recommended replacement).

**Net code change: one line** — `lib/config/supabase_config.dart`:
`static const String defaultModel = 'openai/gpt-oss-20b';`
Confirmed working on device: parse, debrief, weekly insight, category suggestion.

### 3.3 Background gradient "stuck" (same navy all day) — ⚠️ FIX APPLIED, pending eyeball + polish

Two read-only diagnostics proved the **render path is clean** (transparent scaffolds/theme;
nothing painted over the gradient) and the **hour→palette mapping + clock reading are correct**
(5–10 morning, 11–16 midday, 17–20 evening, 21–4 night; widget reads `DateTime.now().hour`).
Root cause: **the palette colour values were all too dark/navy** (a regression from an
originally-vivid design the user remembered).

- **Fix:** replaced the 12 colour values across the 4 palettes in
  **`lib/core/theme/app_colors.dart`** with vivid, clearly-distinct sets — morning
  orange-pink, midday orange, evening light-blue, night deep-blue (dark→bright, top→bottom;
  orientation is `topLeft→bottomRight`, so index 0 = top, no reversal). Added
  **`test/gradient_palette_test.dart`** (correct mapping + **pairwise-distinct** guard + 3
  colours each) so the "all navy" bug can't silently return. Logic/direction/stops untouched.
- **⏳ PENDING user eyeball:** set phone clock to ~08:00 / 14:00 / 18:00 / 23:00, reopen
  Dashboard each time, confirm four clearly different backgrounds + legibility.
- **3 polish items parked (user: "tackle later"):**
  1. **`accentForHour` doesn't track time of day** — accent stays blue while background is
     orange, so the + log button (and other accent bits) clash. Deliberately left out of the
     gradient fix to keep scope tight.
  2. **Top-left corner too dark / not smooth** — the dark top stop reads as an out-of-place
     patch; the transition into it needs smoothing.
  3. **Bottom nav labels hard to read** — the brightened bottom of the gradient washes out the
     nav bar *labels* (Home/Day/Routine/History). The white icons are fine; it's the labels.
     Likely fix: darken just the bottom stop of the offending palettes, or add a subtle scrim
     behind the nav bar.

### 3.4 Can't log a previous day — ✅ DONE (user confirmed "works fine")

**Scope locked:** any past day is loggable/editable; the **only** block is the future (no
start/end later than "now"). (The user's initial idea of a rolling 25-hour window was set
aside — it would bolt a second time-model onto an app built around whole calendar days.)

A read-only diagnostic **reframed the bug**: nothing actually *blocked* past-day logging.
Past-day navigation already worked, the DAO wrote whatever timestamps it was handed, and
display was reactive per-day. The real cause was two things: **no create affordance existed at
all** (`onEmptyHourTap: null` everywhere, no FAB — you could only open the sheet from an
existing entry) and **`LogEntrySheet` was dayless** (defaulted times to today, no date picker).

- **Phase 1 — `LogEntrySheet` made day-aware.** Added optional `day` (defaults to today) +
  `initialHour`. Extracted a pure, testable `resolveInitialTimes(...)`. Unlogged-hours strip
  now per-selected-day. **Added a save-time future guard** (the diagnostic found `_save` had
  none — only the picker did), reusing the existing "Cannot log future time." string. Opened
  the old way (no `day`), behaviour is **byte-identical** to before — proven by equivalence
  tests and user's on-device eyeball of today's + tab.
- **Phase 2 — Day View `onEmptyHourTap` wired.** Tapping an empty hour on any day opens the
  day-aware sheet for that day + hour, using the exact edit-path chrome
  (`showModalBottomSheet(useRootNavigator: true, isScrollControlled: true)`). On **today**, a
  tap on a *future* hour shows "Cannot log future time." and does not open the sheet; the
  current in-progress hour and earlier hours open. Past days: all hours open. Reactivity via the
  existing per-day `.watch()` — no invalidate added. User confirmed the yesterday-log flow works.

**Note:** the empty-hour tap is now live on *today* too (a new second way to start a log there),
by design.

---

## 4. Current state summary

| Area | State |
|---|---|
| Core logging, categories, sleep, routine, visualizations, to-do list | Built (prior sessions) |
| Day View row-layout redesign | Built (chat 6) |
| Usage Stats over-counting fix / reconciliation | Built (chats 4–5) |
| Shared `HourTimeline` + Routine row redesign | ✅ Built this session (Routine device-eyeball owed) |
| AI (Groq via proxy) | ✅ Fixed & confirmed working (model = `openai/gpt-oss-20b`) |
| Background gradient | ⚠️ Fix applied; **4-clock eyeball owed**; 3 polish items parked |
| Past-day logging (empty-hour tap) | ✅ Built & user-confirmed |

- **Tests:** 158 passing at session end. `flutter analyze` clean.
- **Schema:** no `build_runner` / migration this session — schemaVersion unchanged from chat 6.

**Files created this session:** `lib/core/theme/hour_timeline.dart`,
`lib/features/routine/routine_plan_adapter.dart`, and tests
`test/routine_plan_adapter_test.dart`, `test/routine_row_layout_test.dart`,
`test/gradient_palette_test.dart`, `test/log_sheet_day_aware_test.dart`,
`test/day_view_empty_hour_tap_test.dart`.
**Files changed:** `lib/features/day_view/day_view_screen.dart`,
`lib/features/routine/routine_screen.dart`, `lib/config/supabase_config.dart`,
`lib/core/theme/app_colors.dart`, `lib/features/log_entry/log_entry_sheet.dart`.

---

## 5. Still to build / fix (backlog)

**Pending verification (this session's work):**
- **Gradient 4-clock eyeball** — confirm morning/midday/evening/night look clearly different on
  device.
- **Routine screen eyeball** — confirm the new row look and all gestures on device.

**Gradient polish (parked, do as one pass):**
1. Make `accentForHour` track time of day so the accent (e.g. + button) matches the background.
2. Smooth the too-dark top-left corner of the gradient.
3. Fix bottom-nav **label** contrast against the brighter gradient bottom.

**Broken-now still open:**
- **Bottom navbar issue** — user flagged it exists but hasn't described the symptom yet. Ask
  for the exact behaviour before diagnosing.
- **AI-parse submit loop unhardened** (carried from chat 6) — a silent data-loss risk; harden
  before relying on it. (Parse currently works on the new model, but confirm its JSON output
  format is clean on `gpt-oss-20b`, which is a different, "reasoning" model.)

**Deferred Routine interaction bugs** (left unchanged on purpose during the redesign):
- Edit can't change a slot's start hour or weekday.
- Copy-to-days accumulates duplicate rows (no dedupe).
- No overlap prevention (no uniqueness constraint; overlapping slots possible — now lane-packed
  visually).
- Delete is instant swipe with no confirm/undo.
- (Optional) restore an "every-day slot" cue if the dropped dimming/caption is missed.

**Features:**
- Dashboard "right now" strip showing the current routine slot.
- Onboarding / first-run tour (hour-just-ended model, retroactive logging, sleep toggle).
- Supabase sync layer (anonymous → permanent account, push local rows, multi-device;
  `user_id` already reserved on tables).

**Smaller polish:**
- Screen Time card wording.
- Weekly-insight AI prompt missing routine data.
- AI persona consistency across debrief / weekly insight / category suggestion.
- App-name labeling/filtering robustness (Usage Stats).

**AI resilience (new, from this session's outage):**
- **Move the model name out of the app `const` into a Supabase secret** the proxy reads, so the
  next model retirement is a backend swap, not an app rebuild.
- **Surface the real AI error** (even in a debug view) instead of the generic "couldn't reach
  AI" — this outage was three stacked backend problems all hidden behind one fallback message.

**Narrow Screen Time edges / deferred:**
- Only one app reconciled per hour.
- 11 PM–midnight hour never gets a suggestion/carve (deferred).
- Screen Time "honesty layer" (Phase 3) — dropped in chat 5.

---

## 6. Working conventions (how this user likes to work — FOLLOW THESE)

- **Diagnose before fixing.** Never make blind changes. Before any build, run a **read-only
  diagnostic** (changes nothing; reports call-sites/schema/reactivity against real code). This
  session, diagnostics repeatedly overturned wrong assumptions (Routine "chip" premise; the
  gradient being a logic bug; past-day logging being "blocked") — they are load-bearing, not
  ceremony.
- **Ask permission before issuing any Claude Code prompt.** Describe what the prompt will do,
  get a yes, then give it.
- **Spec-first / contract-first.** Lock the full behavioural spec (including edge cases) before
  writing code. Play it back for confirmation when it's dense.
- **Phased builds with verification gates.** Break work into phases; STOP at each gate, report,
  and confirm before continuing. Include explicit verification checklists and, for regression
  fixes, a test that provably fails-before / passes-after (e.g. the gradient pairwise-distinct
  guard, the "today identical when day omitted" equivalence test).
- Every Claude Code prompt is a **complete pasteable markdown block** with a STEP 0 reality-check
  gate, an explicit "Do NOT" section, and verification steps.
- **Modular architecture; reuse existing patterns** rather than inventing parallel ones (this
  session: extract one shared `HourTimeline` so Day View and Routine can't drift; the past-day
  create path reuses the exact edit-path bottom-sheet chrome).
- **Reactivity discipline:** entries, missed-hours, counts are all backed by Drift `.watch()` +
  Riverpod. Deletes/edits flow through reactively. If something doesn't update, **find the
  non-reactive source and report it — don't paper over it with `provider.invalidate`.**
- The user **moves fast once trade-offs are clearly laid out**, and prefers **plain, simple
  language**. Always ask rather than assume.
- Device eyeball is part of every gate: tests prove logic, but the user's phone is the final
  check (especially for anything visual or shared-widget).

---

## 7. Infrastructure notes

- **Supabase:** anonymous auth; `ai_usage` table enforces the 100 req/user/day quota
  server-side. **Free tier auto-pauses the project after ~1 week of inactivity → all AI goes
  down** (happened this session). Keep it active or expect downtime; consider a scheduled ping
  or a paid tier if real users can't tolerate it.
- **Edge Function `groq-proxy`:** validates JWT, increments `ai_usage`, 429s over quota,
  forwards to Groq (`GROQ_API_KEY` from Supabase secrets), streams when `stream: true`.
- **Groq:** free tier has **no time-based key expiry**; a dead key means it was revoked/deleted
  (401 `invalid_api_key`), and Groq **retires model slugs** periodically (404
  `model_not_found`). Current model: **`openai/gpt-oss-20b`**. Rotate the key via
  `supabase secrets set GROQ_API_KEY=...` (no redeploy) or the dashboard Secrets page.
- **Dev environment (Windows + physical Android):** always `flutter run -d android` with a
  device + USB debugging. PowerShell tip: plain `curl` is aliased — use `Invoke-RestMethod`
  (or `curl.exe`) for API tests. Known gotchas: delete any stray `web/` folder (breaks sqlite3
  FFI); keep the project on a short non-OneDrive path; Gradle `org.gradle.parallel=false`,
  `kotlin.incremental=false`; add Defender exclusions. Bottom sheets need
  `useRootNavigator: true`.

---

## 8. Data-integrity note (carried in)

Carves/suggestions write to the log on user confirmation, so any carve confirmed while the old
Usage Stats bugs were live may have corrupted real hours. Worth auditing affected days by hand;
fixes correct future behaviour but don't repair already-written data.
