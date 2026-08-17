# ChronoPlan — Project Plan, Specification & Progress

A Flutter Android app for hourly time-tracking, routine comparison, and AI-driven productivity insights.

> Living document. **Last updated: this session** — History/Reports build, Android Usage Stats build (Phases 1 → 2b + queryEvents swap), core model pivot (removal of "sacred" entries), and Dashboard decluttering. Usage Stats is currently **parked** with an open accuracy bug (see Known Issues).

---

## Core Concept

ChronoPlan tracks how a user spends their day in hourly increments, compares it against a user-defined ideal routine, and provides AI-driven coaching based on the gap between planned and actual time use. **The user — not the app — decides whether a day was good.**

The fundamental log model: at any moment past the top of an hour, the user logs **the hour that just ended**. If it's 6:05 PM, the entry covers 5:00–6:00 PM. The user cannot log future hours. Missed hours from earlier today are surfaced as retroactive log opportunities, never as "lateness" warnings.

> **⚠️ MODEL CHANGE (this session):** The old "real-time entries are sacred and immovable" concept has been **removed**. There is no longer any real-time vs retroactive distinction. **Every entry is an ordinary, fully-editable retrospective record of what the user did that hour.** Nothing is immovable; the user can edit any entry freely. Sections below have been updated to reflect this; the original "sacred entry" wording is preserved only in the Q&A history for context.

---

## Features

### 1. Time Logging
- **Reminder modes** (two only):
  - **Hourly (fixed)** — one notification at the top of every hour
  - **Custom interval** — user-defined minutes (slider, 30–180 min)
- Regular silent notifications, not alarms. No snooze, no escalation.
- Notifications show rotating, contextual quotes (time-of-day and recent-activity aware) instead of blunt "LOG NOW" prompts.
- Tapping a notification opens the log entry sheet pre-filled for the previous completed hour.
- **All logging is retrospective.** Logging an older hour auto-fills only the empty gaps and never silently clobbers an existing entry; but entries are otherwise ordinary and editable (no "sacred" flag).
- **Missed-hours strip** at the top of the log sheet and Day View shows past hours of today with no entry, as tappable chips.
- Each entry = free-text description + one category tag. Time is precise (start/end timestamps), but visually snapped to hour buckets in the UI.

### 2. Categories
- Fully flexible: user-created, renamed, color-coded, archivable.
- Suggested defaults on first use (Work, Exercise, Social, Sleep, Entertainment, Meals, Personal Care, Learning, Admin, Travel).
- A protected **"Screen Time"** system category exists for usage-derived entries.
- Auto-suggested category based on keywords in entry text via AI (always overrideable).
- System categories are protected from deletion; user-created ones can be archived (preserves historical entries, hides from new-entry pickers).

### 3. Sleep Mode
- **Single source of truth: the manual toggle.** Lives in the log entry sheet.
- Animated sun ↔ moon switch — sun = "Awake", moon = "Sleeping since HH:MM".
- Toggle ON records `sleep_start = now`; toggle OFF inserts one Sleep entry covering `sleep_start → now`.
- A **"Still sleeping?"** courtesy notification fires after extended inactivity (~7h). Purely a reminder — **no automatic Sleep entries are ever created by the app.** Forgotten sleep appears as a gap in the missed-hours strip.

### 4. Daily Intention
- Each morning: *"What's the one thing that would make today a win?"* Auto-shown once per day if unset.
- Stored and referenced in the end-of-day debrief.
- **Planned:** expands into a to-do list with one highlighted "win" task. Data model already leaves room; not yet built.

### 5. Routine Builder & Comparison
- **Day-at-a-time vertical timeline (V2):** day-pill tabs, tap-to-fill hourly slots, "copy day to other days" multi-select. UI polish still pending.
- Dashboard shows "what you should be doing now" based on the current day's routine.
- Day View renders routine slots as faded ghost blocks behind logged entries:
  - **Green left edge:** actual entry matches planned slot (≥75% coverage, matching category)
  - **Amber left edge:** partial match
  - **Red left edge:** missed planned slot
- **No app verdict.** The user decides whether the day was good via thumbs-up/down (`daily_intentions.verdict_positive`).

### 6. Visualizations
- **Daily view:** pie chart of time by category, on the Dashboard.
- **Weekly view — BUILT this session:** History/Reports screen with an fl_chart stacked bar chart, one bar per day, segmented by category.
  - Week runs **Sunday → Saturday**. **Week view only** (no month view). Prev/next steps one week at a time.
  - **Trend summary row:** total hours logged this week, top category, change vs. previous week.
  - Tapping a day's bar drills into Day View at that date.
  - The **weekly AI insight card** is reused here (and, as of this session, now lives *only* here — removed from the Dashboard).

### 7. Android Usage Stats Integration *(BUILT this session, then PARKED — see Known Issues)*
The most distinctive feature in the spec. Substantial progress was made, but it is **currently disabled/parked** due to an unresolved usage-accuracy bug.

**What it's meant to do:**
- Read per-hour app foreground usage via Android's `UsageStatsManager`.
- **Empty hour with detected usage →** surface a suggestion (a dedicated "Suggestions to review" card) to log that time; user confirms + categorizes (defaults to Screen Time, asks every time).
- **Logged hour with detected usage →** propose a **user-confirmed carve-out**: the detected app's time carves out of the logged entry into its own entry (default category Screen Time, editable at confirm), leaving the remainder in the original category. Shown **side by side in the same Day View row** (e.g. "Learning 47m | YouTube 13m"). Totals always sum to the real hour; nothing overlaps.
  - **Auto-suppress** when the detected app's name already appears in the log's description (so logging "watched youtube" won't prompt to carve YouTube).
  - **≥10 min threshold** before a suggestion or carve is proposed.
- **Honesty layer (Phase 3, NOT built):** cross-reference logged focus blocks against actual usage and surface discrepancies non-judgmentally via the AI coach. Blocked until usage numbers are trustworthy.

**Data source:** originally the `app_usage` package; **swapped mid-build to a hand-rolled Kotlin `queryEvents` method channel** after discovering `app_usage` (built on `queryUsageStats`) only returns **daily** aggregates — a one-hour query returned an app's whole-day total (e.g. YouTube at 151m for a single hour). `queryEvents` returns raw foreground/background transition events, reconstructed into sessions in Dart.

### 8. AI Features (powered by Groq + Llama 3.1 8b Instant)
- **No user setup required.** The user never enters an API key.
- Architecture: Flutter → Supabase anonymous auth → Supabase Edge Function (`groq-proxy`) → Groq → back.
- Per-user daily quota: **100 requests/day**, enforced server-side via the `ai_usage` table.
- Features: natural-language log parsing, category auto-suggestion (debounced), weekly insight summary, streaming day-debrief chat (SSE), Sunday 8 PM weekly reflection notification.
- **Selectable AI coach persona** (Settings): *Drill Sergeant*, *Friendly Coach*, *Neutral Analyst*.
- **Graceful fallback:** all AI features handle network failure, rate limit (429), and missing auth without blocking core functionality. The core app works fully offline.

---

## Technical Stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | Flutter (Android first) | Clean enough to extend to iOS later |
| State management | Riverpod | Standard for async-heavy Flutter |
| Local database | Drift (SQLite) | Fully offline-first |
| Backend | Supabase | Anonymous auth + Edge Functions + Postgres; future sync layer |
| Notifications | flutter_local_notifications | Scheduled recurring + contextual quotes |
| Charts | fl_chart | Daily pie + weekly stacked bar |
| Android usage | **Hand-rolled Kotlin `queryEvents` method channel** | `app_usage`/`queryUsageStats` only give daily aggregates, unusable for per-hour |
| AI model | Llama 3.1 8b Instant (via Groq) | Free-tier-friendly, fast, sufficient for v1 |
| AI proxy | Supabase Edge Function (`groq-proxy`) | Holds Groq key server-side; enforces quota; supports streaming |
| AI auth | Supabase anonymous auth | Zero-friction; each install gets a device-bound user |

---

## UI / Design Direction

**Style:** Glassmorphism, dark-mode-first. Semi-transparent cards (10–20% opacity) with `BackdropFilter` blur, `ClipRRect` rounded corners (16–24px), subtle 1px light border, soft shadows.

**Dynamic background gradient**, shifting with time of day: morning oranges/pinks → midday blues/cyans → evening purples/deep oranges → night navy/indigo.

**Typography:** Manrope. **Category palette:** 16-color picker; 10 curated colorblind-aware defaults that hold up at low opacity.

**Navigation:** glassmorphic bottom nav with center "+" log button — Dashboard | Day View | **[+ Log]** | Routine | History. Top bar: app name centered, app icon (→ About) top-left, user icon (→ Profile) top-right. Settings lives inside Profile.

**Key screens (current):**
- **Dashboard** — gradient, current-hour card, daily intention card, daily pie chart. *(This session: weekly insight/debrief card REMOVED from here — now only in History. Usage/Screen Time content REMOVED from here — now on its own screen.)*
- **Log Entry** — bottom-sheet modal: sleep toggle, missed-hours strip, description + category suggestion, parse-from-text.
- **Day View** — vertical 24h timeline, planned vs actual blocks (green/amber/red edges), current-time line, date nav, tap-to-edit, and **side-by-side usage carve proposals** in the row.
- **History/Reports** — weekly stacked bar chart (Sun–Sat), trend summary row, weekly AI insight card, drill-down by day.
- **Screen Time (new, dedicated)** — per-app usage list, moved off the Dashboard. Hosts the temporary usage debug view.
- **Routine Builder** — day-pill tabs + vertical timeline + copy-to-days.
- **Settings / Profile / About / Categories / Debrief** — as previously built.

---

## This Session — Changelog

**Built**
- **History/Reports screen + weekly bar chart** (fl_chart). Sun–Sat weeks, week-view-only, prev/next by week, trend summary row (total hours, top category, delta vs last week), tap-a-bar → Day View, weekly AI insight card reused here.
- **Usage Stats Phase 1** — `PACKAGE_USAGE_STATS` permission + deep-link to Usage Access settings, value-prop card gated on `appOpenCount >= 2`, protected "Screen Time" category, usage service, temporary debug preview.
- **Usage Stats Phase 2a** — "Suggestions to review" card for empty hours (today-only, ≥10 min, default Screen Time, ask every time, confirm/dismiss).
- **Usage Stats Phase 2b (carve-out model)** — in-row, user-confirmed carve of detected app time out of a logged hour; name-match auto-suppress; ≥10 min threshold. *(Replaced an earlier, scrapped "automatic deduction/reconciliation" design.)*
- **Phase 1.5 — data-source swap** to a hand-rolled Kotlin `queryEvents` method channel (chosen over the `usage_stats` package: unverified publisher, low adoption, vs. ~50 lines of Kotlin we control).
- **UI declutter** — weekly debrief/insight removed from Dashboard (kept in History); Screen Time display moved to its own dedicated screen.

**Decided**
- **No more "sacred" entries** — all logs are ordinary editable retrospective records.
- **Contradiction handling** for usage vs. logs resolved via the carve-out + confirm + name-match-suppress model (no double-counting, totals always = real time).
- Detected usage labeled **per-app**; carve proposals are **tappable/actionable**, not passive.

**Parked** — see Known Issues.

---

## Known Issues / Open Bugs

### Usage Stats over-counting (PARKED — blocks the whole feature)
Despite the `queryEvents` swap and multiple fix passes, per-hour usage is still badly inflated:
- Reported **total screen time of ~45h 47m for a single day** (impossible; >24h), with **Snapchat alone at ~20h** when actually used <5 min.
- Earlier symptom: an app (e.g. Instagram) pinned to **60m every hour through the night** while the user was asleep and not on the phone.

**Diagnosis (confirmed direction):** foreground sessions are **not being closed when the screen turns off**. Android frequently does **not** emit `ACTIVITY_PAUSED` before sleep, so the last-open app stays "foreground" indefinitely, and each subsequent hour re-attributes the full hour to it. Sessions also appear to overlap/double-count (durations exceeding 60m/hour prove the per-hour clamp and single-foreground invariant aren't holding).

**Intended fix (not yet successful) for when this is revisited:**
1. Reconstruct **one full-day foreground timeline**, then slice into hour buckets — do **not** query hour-by-hour (that's what makes "which app was open at the hour's start?" a guess that fills idle/sleep hours).
2. Close a session at the **earliest** of: next `ACTIVITY_PAUSED`/`MOVE_TO_BACKGROUND` for that package, next `ACTIVITY_RESUMED` for a *different* package (single-foreground), a **screen-off / `SCREEN_NON_INTERACTIVE`** event, a **keyguard/lock** event, `DEVICE_SHUTDOWN`, or timeline end. **Do not** close on `ACTIVITY_STOPPED` alone (fires while merely backgrounded → over-counts).
3. Hard invariants: no session or per-app-per-hour total may exceed the bucket; foreground sessions never overlap; no negative/zero durations. Clamp + surface violations in the debug view rather than emitting bad data.
4. A **raw-events + reconstructed-sessions debug view** already exists — use it to diagnose (read actual timestamps) rather than guessing from the summary card.

### Suggestion/manual-log overlap
Accepting a Screen Time suggestion and then logging manually into the same hour produces **overlapping entries** — the "entries never overlap" invariant isn't enforced across the suggestion-created entry and a subsequent manual entry. Needs the manual-log path to reconcile against suggestion-created entries in the same bucket.

### App labeling / filtering (partially addressed)
Raw `queryEvents` surfaced internal package codenames and system packages (e.g. `com.facebook.katana` = Facebook, `com.facebook.orca` = Messenger, plus Launcher/Android/Wellbeing/Dialer). Fix direction: resolve display labels via `PackageManager.getApplicationLabel`, and filter packages with no launcher intent (`getLaunchIntentForPackage(pkg) == null`) rather than a hardcoded blocklist — but note a filter pass once over-filtered to an **empty list**, so any per-entry failure must degrade per-entry, never wipe the whole result.

> **Data-integrity note:** because carves/suggestions write to the log on user confirmation, any carve confirmed while these bugs were live may have corrupted real hours (e.g. a full slot converted to Screen Time). Worth auditing affected days by hand; fixes correct future behavior but don't repair already-written data.

---

## Still To Build (backlog)

- **Phase 3 — Usage "honesty layer"** (AI coaching on logged-vs-actual discrepancies). *Blocked on Usage Stats accuracy.*
- **Supabase sync layer (full)** — anonymous → permanent account upgrade, push local rows, multi-device sync. (`user_id` already reserved on every table.)
- **To-do list expansion of Daily Intention** — multi-task list with one highlighted "win" task; data model ready.
- **Onboarding flow** — first-launch tour of the core concepts (hour-just-ended model, retroactive logging, sleep toggle). No API-key step needed.
- **Routine Builder UI polish** — enumerate specific rough edges next iteration.
- **Day View overlay refinement** — verify green/amber/red edge logic against real use.
- **AI polish** — persona consistency across debrief / weekly insight / category suggestion; consider a stronger model for the debrief specifically (the proxy abstracts the provider, so it's a near-trivial swap).

---

## Key Architecture Decisions (Q&A history)

> Preserved for context. Where superseded this session, the update is noted inline.

1. **Log time granularity — Hybrid.** Store precise `start_time`/`end_time` as truth; display/comparison snap to hour buckets via a slicing utility.
2. **Overlapping entries.** *(Original: "real-time entries are sacred; retroactive auto-splits around them.")* **Superseded:** no sacred entries; retroactive logging auto-fills empty gaps and doesn't silently overwrite, but all entries are editable. Usage carves go through the normal edit path.
3. **Real-time vs retroactive toggle — removed.** *(Now moot: there is no real-time/retroactive distinction at all.)*
4. **Routine slot duration — day-at-a-time V2 timeline** with copy-to-days.
5. **Supabase / accounts — anonymous-first.** Every install becomes an anonymous Supabase user; `user_id` on every table; real accounts deferred to when sync ships.
6. **AI provider — Groq + Llama 3.1 8b Instant** via Supabase Edge Function proxy; 100 req/user/day; no user API key.
7. **End-of-day verdict — user decides.** Thumbs up/down per day; no app-generated score.
8. **Sleep auto-detection — removed (data layer).** Manual toggle only; "Still sleeping?" notification is a courtesy reminder with no data side effects.
9. **Streak metric — removed.**

---

## Supabase / Infrastructure Notes

**Project:** Singapore region. Anonymous auth enabled. `ai_usage` table (`user_id uuid`, `date date`, `requests int`, PK `(user_id, date)`), RLS with "users read own usage" (SELECT only; writes via Edge Function service_role).

**Edge Function `groq-proxy`:** validates JWT, upserts/increments `ai_usage`, rejects with 429 if `requests > 100`/day, forwards to Groq (`GROQ_API_KEY` from Supabase secrets), streams if `stream: true`.

**Free-tier headroom:** Edge Functions 500k invocations/month. **Supabase free tier pauses the project after ~1 week of inactivity — keep the dashboard active or expect AI downtime.** Groq free-tier limits are shared across users; the cliff is ~14,400 requests/day total — monitor `ai_usage` as the user base grows.

**Key rotation:** Groq key via `supabase secrets set GROQ_API_KEY=...` (no redeploy). Supabase anon key embedded in app; safe to expose; rotating needs an app update.

---

## Development Notes / Troubleshooting Log (Windows + Android)

- **`sqlite3` FFI compile errors** ("Only JS interop members may be 'external'") — stray `web/` folder confuses the build target. Delete `web/`, use `sqlite3_flutter_libs` (not `sqlite3` directly), `flutter pub get`, `flutter run -d android`.
- **Build defaulting to Windows desktop** — always `flutter run -d android` with a physical device + USB debugging.
- **Gradle Kotlin incremental cache errors** (`Could not close incremental caches`) — Windows file locking. Move project to a short path on a non-system drive, off OneDrive; set `org.gradle.parallel=false`, `org.gradle.workers.max=1`, `kotlin.incremental=false`, `kotlin.compiler.execution.strategy=in-process`; add Defender exclusions; build from a clean terminal.
- **Debrief stream crash (`_dependents.isEmpty`)** — SSE callback after widget disposal. Store the subscription, cancel in `dispose()`, guard `setState` with `if (!mounted) return;`.
- **Sleep entry showing 16h** — auto-detect inserted a duplicate with `end_time = now`; root cause `lastForegroundAt` never updated during sleep. Fixed by removing auto-detect data insertion entirely.
- **Bottom sheets under bottom nav** — add `useRootNavigator: true` to all `showModalBottomSheet` sites.
- **Old FAB bleeding through nav** — pre-refactor log button never deleted; removed.
- **Sleep toggle mistaken for theme toggle** — moved from AppBar to the log sheet as an animated sun ↔ moon switch with label.
