# ChronoPlan — Project Plan, Specification & Progress

A Flutter Android app for hourly time-tracking, routine comparison, and AI-driven productivity insights.

> Living document. Last updated at the end of the AI migration session (Claude → Groq via Supabase proxy).

---

## Core Concept

ChronoPlan tracks how a user spends their day in hourly increments, compares it against a user-defined ideal routine, and provides AI-driven coaching based on the gap between planned and actual time use. The user — not the app — decides whether a day was good.

The fundamental log model: at any moment past the top of an hour, the user logs **the hour that just ended**. If it's 6:05 PM, the entry covers 5:00–6:00 PM. The user cannot log future hours. Missed hours from earlier today are surfaced as retroactive log opportunities, never as "lateness" warnings.

---

## Features

### 1. Time Logging
- **Reminder modes** (two only):
  - **Hourly (fixed)** — one notification at the top of every hour
  - **Custom interval** — user-defined minutes (slider, 30–180 min)
- Regular silent notifications, not alarms. No snooze, no escalation.
- Notifications show rotating, contextual quotes (time-of-day and recent-activity aware) instead of blunt "LOG NOW" prompts.
- Tapping a notification opens the log entry sheet pre-filled for the previous completed hour.
- **Retroactive logging is automatic, not a toggle:** if the user logs the hour that just ended, it's a real-time entry (sacred, immovable). If they log an older hour, the system auto-fills only the gaps and never overwrites real-time entries. The user never sees the words "real-time" or "retroactive."
- **Missed-hours strip** at the top of the log sheet and Day View shows past hours of today with no entry, as tappable chips.
- Each entry = free-text description + one category tag. Time is precise (start/end timestamps), but visually snapped to hour buckets in the UI.

### 2. Categories
- Fully flexible: user-created, renamed, color-coded, archivable.
- Suggested defaults on first use (Work, Exercise, Social, Sleep, Entertainment, Meals, Personal Care, Learning, Admin, Travel).
- Auto-suggested category based on keywords in entry text via AI (always overrideable).
- System categories are protected from deletion; user-created ones can be archived (preserves historical entries, hides from new-entry pickers).

### 3. Sleep Mode
- **Single source of truth: the manual toggle.** Lives in the log entry sheet.
- Animated sun ↔ moon switch — sun = "Awake", moon = "Sleeping since HH:MM".
- Toggle ON: records `sleep_start = now`.
- Toggle OFF: inserts one Sleep entry covering `sleep_start → now`.
- A **"Still sleeping?"** courtesy notification fires after extended inactivity (~7h). It is purely a reminder — tapping it opens the app and does nothing else. **No automatic Sleep entries are ever created by the app.** If a user forgets to toggle sleep, the time appears as a gap and surfaces in the missed-hours strip for retroactive logging.

### 4. Daily Intention
- Each morning, the app asks: *"What's the one thing that would make today a win?"*
- Auto-shown on first app open of the day if not yet set (once per day only).
- Stored and referenced in the end-of-day debrief.
- Eventually expands into a to-do list with one "win" task highlighted; current version is single-intention only, with the data model leaving room for the expansion.

### 5. Routine Builder & Comparison
- Currently using the **day-at-a-time vertical timeline** (V2) — day-pill tabs at the top, tap-to-fill hourly slots, "copy day to other days" multi-select. UI changes and minor bug fixes still pending.
- Dashboard shows "what you should be doing now" based on the current day's routine.
- Day View renders routine slots as faded ghost blocks behind logged entries:
  - **Green left edge:** actual entry matches planned slot (≥75% time coverage, matching category)
  - **Amber left edge:** partial match
  - **Red left edge:** missed planned slot
- **No app verdict.** The app surfaces the gap; the user decides whether the day was good via a thumbs-up/down (stored in `daily_intentions.verdict_positive`).

### 6. Visualizations
- **Daily view:** pie chart of time by category, on the Dashboard.
- **Weekly view (planned):** stacked bar chart in History/Reports, one bar per day, segmented by category.

### 7. Android Usage Stats Integration *(deferred)*
- `UsageStatsManager` via method channel or the `app_usage` package.
- `PACKAGE_USAGE_STATS` permission requested contextually after a couple days of app use (not on first launch), with a clear value-prop card.
- Auto-suggests log entries from detected app usage blocks (user confirms + categorizes).
- **Honesty layer** — cross-references logged focus blocks against actual phone usage in that window, surfacing discrepancies non-judgmentally through the AI coach.
- Passive "Screen Time" category populates automatically.
- This is the most distinctive feature in the spec. Deferred to a later phase but explicitly not cut.

### 8. AI Features (powered by Groq + Llama 3.1 8b Instant)
- **No user setup required.** AI features work out of the box. The user never enters an API key.
- Architecture: Flutter → Supabase anonymous auth → Supabase Edge Function (`groq-proxy`) → Groq → back.
- Per-user daily quota: **100 requests/day**, enforced server-side via the `ai_usage` table.
- Features:
  - **Natural language log parsing** — paste a block of text, AI splits it into multiple entries with guessed categories.
  - **Category auto-suggestion** — debounced as the user types in the description field; suggested category appears as a highlighted chip (tap to accept).
  - **Weekly insight summary** — auto-loaded card on Dashboard; 3–4 sentence plain-English summary with trends and one concrete suggestion.
  - **Day debrief chat** — streaming SSE chat, opens with full context (today's logs, routine, gaps, intention, verdict).
  - **Sunday weekly reflection notification** — scheduled at 8 PM Sunday; tapping opens the debrief / insight.
- **Selectable AI coach persona**, switchable anytime in Settings:
  - *Drill Sergeant* — blunt, no-excuses tone
  - *Friendly Coach* — warm, encouraging, realistic
  - *Neutral Analyst* — data-only, no emotional framing
- **Graceful fallback:** all AI features handle network failure, rate limit (429), and missing auth without blocking core functionality. Core app (logging, dashboard, routine) works fully without AI.

---

## Technical Stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | Flutter (Android first) | Architected cleanly enough to extend to iOS later |
| State management | Riverpod | Standard for async-heavy Flutter apps |
| Local database | Drift (SQLite) | Fully offline-first; app must work without connectivity |
| Backend | Supabase | Anonymous auth + Edge Functions + Postgres; will also host eventual sync layer |
| Notifications | flutter_local_notifications | Scheduled recurring + contextual quote rotation |
| Charts | fl_chart | Pie chart (daily) + stacked bar chart (weekly) |
| Android usage stats *(deferred)* | Method channel to `UsageStatsManager`, or `app_usage` package | Native bridge required, no iOS equivalent available to indie devs |
| AI model | Llama 3.1 8b Instant (via Groq) | Free-tier-friendly, fast, sufficient for log parsing and coaching at v1 quality bar |
| AI proxy | Supabase Edge Function (`groq-proxy`) | Holds Groq key server-side; enforces per-user quota; supports streaming |
| AI auth | Supabase anonymous auth | Zero-friction; each install gets a device-bound user automatically |

---

## Key Architecture Decisions (Q&A Log)

### 1. Log entry time granularity
**Decision: Hybrid.** Store precise free-range timestamps (`start_time`, `end_time`) as the source of truth — never lose precision. Display and routine-comparison logic snap to hour buckets via a slicing utility function. Preserves accuracy from real usage data (e.g. Android Usage Stats) while keeping charts and comparisons simple.

### 2. Overlapping entries
**Decision:** Real-time entries are sacred and immovable. Retroactive entries auto-split into separate rows around any existing real-time entries, filling only the empty gaps in the time window. No conflict warnings, no manual resolution UI. A missed-hours strip (not a conflict warning) surfaces unfilled time slots at the top of the log sheet.

### 3. Real-time vs retroactive — toggle removed
**Decision:** No user-facing distinction. The app decides automatically: logging the hour that just ended = real-time. Logging an older hour = retroactive. The user just logs; the system handles the rest.

### 4. Routine slot duration
**Decision (current):** Day-at-a-time vertical timeline (V2). Tap an hour to fill it; "copy this day to other days" multi-select reduces the 7-day entry burden. UI to be polished later.

### 5. Supabase / user accounts
**Decision:** Anonymous-first. Every install becomes an anonymous Supabase user automatically on first launch — no signup, no email. `user_id` is on every table (currently used by `ai_usage`; reserved on log/routine tables for future sync). Real account creation (email/password) is deferred to whenever sync becomes a feature.

### 6. AI provider
**Decision:** Groq with Llama 3.1 8b Instant, accessed via a Supabase Edge Function proxy. The user never enters an API key. Per-user quota of 100 requests/day enforced server-side. Trade-off: model is less capable than Claude for nuanced coaching, but speed and zero-friction onboarding win for v1.

### 7. End-of-day verdict
**Decision:** The user decides, not the app. Thumbs-up / thumbs-down stored per day. The AI debrief receives both the routine-vs-actual gap and the user's verdict as context. The app never produces a productivity score.

### 8. Sleep auto-detection
**Decision: Removed (data layer only).** The app never automatically creates Sleep entries. The "Still sleeping?" notification remains as a courtesy reminder after extended inactivity, but tapping it does nothing beyond opening the app. The manual toggle is the only path that creates Sleep entries. (Original auto-detect was removed after it created duplicate entries when its `lastForegroundAt` state went stale during sleep mode.)

### 9. Streak metric
**Decision: Removed.** A streak chip was considered (days with ≥N hours logged) but ultimately cut.

---

## UI / Design Direction

**Style:** Glassmorphism, dark-mode-first.

- Semi-transparent cards (10–20% opacity) with backdrop blur (`BackdropFilter` + `ImageFilter.blur`)
- `ClipRRect` for rounded corners (16–24px radius)
- Subtle 1px light border for glass edge definition
- Soft shadows underneath cards for a floating effect

**Dynamic background gradient**, shifting with time of day:
- Morning (5am–11am): soft oranges/pinks
- Midday (11am–5pm): blues/cyans
- Evening (5pm–9pm): purples/deep oranges
- Night (9pm–5am): deep navy/indigo

**Typography:** Manrope — clean geometric sans-serif with strong number rendering.

**Category color palette:** 16-color picker for user customization; defaults use 10 curated colorblind-aware colors that hold up at low opacity for chart use.

**Navigation:** Instagram-style bottom nav (glassmorphic) with center "+" log button.
- 5 slots: Dashboard | Day View | **[+ Log]** | Routine | History
- Center "+" is larger, accent color, opens the log entry bottom sheet (not a separate route)
- Top bar: app name centered, app icon (→ About) top-left, user icon (→ Profile) top-right
- Settings lives inside Profile, not as a top-level destination

**Key screens:**
- **Dashboard** — gradient background, current-hour card, daily intention card, daily pie chart, weekly insight card, debrief entry point
- **Log Entry** — bottom-sheet modal, includes sleep toggle, missed-hours strip, description field with category suggestion, parse-from-text button
- **Day View** — vertical 24-hour timeline, planned vs actual blocks with green/amber/red edges, current-time red line, date navigation
- **Routine Builder** — day-pill tabs + vertical timeline + copy-to-days
- **History/Reports (planned)** — weekly stacked bar chart, trends, drill-down by day
- **Settings** — persona selector, reminder mode, "AI powered by Groq" note (no API key field anymore)
- **Profile** — overall stats, links to Settings, Category Management, About
- **About** — app version, credits
- **Categories** — full CRUD with 16-color picker, archive-not-delete
- **Debrief** — streaming SSE chat with verdict (thumbs up/down)

**Performance note:** Test `BackdropFilter` blur on lower-end Android early. Reduce blur intensity if frame drops appear.

---

## Build Progress

### Completed ✅

**Foundation & Data Layer**
- Drift schema with 5 tables (categories, log entries, routine slots, intentions, settings), migrated to v2 with `verdict_positive`
- 10 default categories seeded on first launch
- Real-time log entry logic (sacred, never overwritten)
- Retroactive entry with auto-split around real-time blockers
- Offline-first — Supabase `user_id` nullable on every table

**UI System**
- Time-based dynamic gradient background (morning/midday/evening/night)
- Glassmorphism UI system (GlassCard)
- Manrope typography + dark theme
- Instagram-style bottom nav with center "+" log button
- Top bar with app icon (→ About) and user icon (→ Profile)

**Screens**
- Dashboard (current-hour card, live clock, daily pie chart, daily intention card, weekly insight card, debrief entry)
- Day View (24h timeline, entry blocks, current-time line, date nav, ghost-block routine overlay with green/amber/red edges, tap-to-edit)
- Log entry sheet (defaults to previous completed hour, missed-hours strip, AI category suggestion chip, parse-from-text via AI, sleep toggle, edit-existing-entry support)
- Routine Builder V2 (day-pill tabs + tap-to-fill timeline + copy-to-other-days)
- Settings (persona selector, reminder mode, interval slider; API key UI removed after Groq migration)
- Profile screen (entry points to Settings, Categories, About)
- About screen
- Categories management (CRUD with 16-color picker, archive instead of delete, system categories protected)
- Debrief screen (streaming SSE chat, blinking cursor, thumbs-up/down verdict persisted)

**Sleep Mode**
- Manual toggle in log entry sheet with animated sun ↔ moon switch
- Sleep entry inserted on toggle-off (`sleep_start → now`)
- "Still sleeping?" courtesy notification fires after extended inactivity (no data side effects)
- All automatic Sleep entry creation removed
- One-time dedup migration removes leftover duplicate Sleep entries from the old auto-detect bug

**Notifications**
- Hourly fixed notifications (quote-aware payloads)
- Custom interval notifications
- Sunday 8 PM weekly reflection notification → opens debrief
- Boot receiver reschedules notifications after device reboot

**AI Layer**
- Supabase project created, anonymous auth enabled
- `ai_usage` table with RLS + per-user-read policy
- `groq-proxy` Edge Function deployed: validates JWT, enforces 100/day quota, forwards to Groq, streams responses
- Flutter `GroqService` with same public API as old ClaudeService
- AI features wired: log parsing, category suggestion, weekly insight, streaming debrief
- Persona instructions threaded through all AI calls
- Graceful fallback for rate limit (429) and network errors
- Old `ClaudeService` and BYOK API key UI removed entirely

**Daily Intention**
- Morning auto-prompt once per day if intention not set
- Highlighted on Dashboard with edit dialog
- Schema-prepared for future to-do list expansion

### Not Yet Built ⏳

- **Weekly bar chart** — fl_chart installed, no History/Reports screen yet
- **History / Reports screen** — browse past days, weekly summary, date range selector, tap-to-drill-down
- **Android Usage Stats integration** — `UsageStatsManager` via method channel; permission flow after `appOpenCount >= 2`; auto-suggest log entries; honesty layer
- **Supabase sync layer (full)** — anonymous → permanent account upgrade, push local rows to Supabase, multi-device sync
- **Routine builder UI polish** — known UI rough edges to address after other features land
- **To-do list expansion of Daily Intention** — multi-task list with one highlighted "win" task; data model is ready
- **Onboarding flow** — first-launch explainer (no API key step needed anymore, but app concepts could use a quick tour)

---

## Development Notes / Troubleshooting Log

### Windows + Android setup issues

**1. `sqlite3` FFI compile errors ("Only JS interop members may be 'external'")**
Caused by a stray `web/` folder in the project root confusing the build target. Fix: delete the `web/` folder (Android-only project), ensure `sqlite3_flutter_libs` is used instead of `sqlite3` directly in `pubspec.yaml`, then `flutter pub get` and `flutter run -d android`.

**2. Build defaulting to Windows desktop instead of Android**
Fix: always specify the target explicitly with `flutter run -d android`, and ensure a physical device is connected via USB with USB Debugging enabled.

**3. Gradle Kotlin incremental cache errors (`Could not close incremental caches`)**
Caused by Windows file locking (antivirus, Search Indexer, OneDrive sync) during Gradle's incremental Kotlin compilation. Fixes in order of impact:
- Move project to a short path on a non-system drive (e.g., `F:\chronoplan`)
- Move OFF OneDrive-synced folders entirely
- Add to `android/gradle.properties`:
  ```
  org.gradle.parallel=false
  org.gradle.workers.max=1
  kotlin.incremental=false
  kotlin.compiler.execution.strategy=in-process
  ```
- Add Windows Defender exclusions for the project folder, `.gradle` folder, and `java.exe` / `gradle.exe` / `kotlinc.exe`
- Close VS Code, Android Studio, File Explorer pointed at the project, then build from terminal

### Bugs caught and fixed

- **Debrief stream crash (`_dependents.isEmpty` assertion):** SSE stream callback firing after widget disposal. Fixed by storing the StreamSubscription, cancelling in `dispose()`, and guarding all `setState` calls with `if (!mounted) return;`.
- **Sleep entry showing 16h instead of 7h 42m:** Auto-detect was firing after the manual toggle and inserting a duplicate Sleep entry whose `end_time` was `DateTime.now()`. Root cause: `lastForegroundAt` was never updated during sleep mode. Fix initially patched the resets; ultimately auto-detect data insertion was removed entirely (notification kept).
- **Bottom sheets rendering under bottom nav:** Modal sheets missing `useRootNavigator: true`. Fixed across all `showModalBottomSheet` call sites.
- **Old FloatingActionButton bleeding through behind bottom nav:** Pre-refactor log button never deleted, just covered. Removed entirely.
- **Sleep toggle visually mistaken for a theme toggle:** Moved from AppBar (sun/moon icon) to the log entry sheet (animated sun ↔ moon switch with text label).

---

## Supabase / Infrastructure Notes

**Project setup**
- Project provisioned in Singapore region
- Anonymous auth enabled (Authentication → Providers → Anonymous Sign-Ins → on)
- `ai_usage` table: `user_id uuid` + `date date` + `requests int`, primary key on `(user_id, date)`
- RLS enabled with policy "users read own usage" (SELECT only; writes happen via Edge Function with service_role)

**Edge Function: `groq-proxy`**
- Validates `Authorization: Bearer <jwt>` header against Supabase auth
- Upserts `ai_usage` row, increments `requests`
- Rejects with 429 if `requests > 100` for today
- Forwards body to `https://api.groq.com/openai/v1/chat/completions` with `GROQ_API_KEY` from Supabase secrets
- Streams response back if `stream: true`, otherwise returns JSON

**Free tier headroom**
- Supabase Edge Functions: 500k invocations/month
- Supabase free tier pauses project after 1 week of inactivity — keep the dashboard active or expect downtime
- Groq free tier rate limits are shared across all users — monitor `ai_usage` table for daily totals as the user base grows; the cliff exists around ~14,400 requests/day total

**Key rotation**
- Groq key: stored as `GROQ_API_KEY` in Supabase secrets. To rotate: get new key from console.groq.com, run `supabase secrets set GROQ_API_KEY=...`, no redeploy needed.
- Supabase anon key: embedded in app via `SupabaseConfig`. Safe to expose; rotating requires an app update.

---

## Decisions Still Open / Next Steps

- **Build History/Reports screen** — weekly bar chart, drill-down to Day View
- **Routine builder UI polish** — list specific issues during next iteration
- **Onboarding flow** — first-launch tour
- **Android Usage Stats integration** — permission flow + honesty layer (the spec's most distinctive feature)
- **Supabase sync layer** — anonymous → permanent account, multi-device sync
- **Day View overlay refinement** — verify green/amber/red edge logic feels right after real-world use
- **Test persona consistency across all three AI features** — debrief, weekly insight, category suggestion should feel like the same voice
- **Consider model upgrade for debrief specifically** — Llama 8b is fine for parsing/suggestion; debrief may benefit from a stronger model if responses feel flat
