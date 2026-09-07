# ChronoPlan — Session Handoff (Chat 8)

A handoff document so a fresh chat can pick up ChronoPlan development with full context.
**ChronoPlan is a Flutter Android app** for hourly retrospective time-logging, routine
comparison, and AI-driven productivity coaching.

> This is the chat-8 handoff. Prior handoffs are `ChronoPlan_1.md` … `_7.md`.
> **Headline of this session:** everything needed before handing the app to friends for
> testing is now built — AI-parse hardening, the Dashboard routine strip, usage analytics
> (counters only, backend + app), and first-run onboarding. **Tests: 226 passing,
> `flutter analyze` clean. No schema change this session — schemaVersion still 7.**

---

## 1. What ChronoPlan is (core context)

**Core concept**
- Tracks how the day is spent in **hourly increments**, compares it against a user-defined
  **ideal routine**, and gives **AI coaching** on the gap.
- **The user — not the app — decides whether a day was good** (thumbs up/down in the
  Debrief; no app-generated score for the *day*).
  - ⚠️ Nuance confirmed this session: the app **does** auto-grade **routine adherence**
    (green/amber/red bars in Day View via `RoutineVerdict`). "The app never scores you" is
    only true of the *day rating*. The onboarding copy was reworded to reflect this.
- **Log model:** at any moment past the top of an hour, the user logs *the hour that just
  ended*. **No future logging** (enforced in both the picker and at save). Missed hours
  surface as retroactive opportunities, never as "lateness." Every entry is an ordinary,
  fully-editable retrospective record.
  - Nuance: "log the hour that just ended" is the **default pre-fill**, not a restriction —
    any past time is pickable, and past-day logging seeds that day.

**Tech stack**
- Flutter (Android first), Riverpod, Drift (SQLite, offline-first, **schemaVersion 7**),
  Supabase (anonymous auth + Edge Functions + Postgres), `flutter_local_notifications`,
  `fl_chart`, `flutter_slidable`, `go_router`, `shared_preferences`.
- Android per-hour usage: hand-rolled Kotlin `queryEvents` method channel.
- **AI** via **Groq**, proxied through the Supabase Edge Function `groq-proxy`, anonymous
  auth, 100 req/user/day quota, no user API key. Selectable persona (Drill Sergeant /
  Friendly Coach / Neutral Analyst). Graceful offline fallback.
- **AI model: `openai/gpt-oss-20b`** — a single `const` in `lib/config/supabase_config.dart`.

**UI direction**
- Glassmorphism, dark-mode-first. Semi-transparent `GlassCard`s with blur + rounded corners.
- Time-of-day dynamic background gradient (`TimeGradientBackground`). Manrope typography.
  Colourblind-aware category palette.
- Bottom nav: Home (Dashboard) | Day | [+ Log] | Routine | History. `AppShell` hosts the nav
  as a persistent `ShellRoute`; full-page routes (`/debrief`, `/settings`, `/profile`,
  `/about`, `/categories`, `/screen-time`, `/debug-usage`, and now `/onboarding`) are
  declared as **siblings outside** the `ShellRoute`, so they show with no bottom nav.

**Built before this session** (chats 1–7)
- Time logging (hourly/custom-interval reminders, silent notifications, contextual quotes,
  unlogged-hours strip, free-text + one category tag per entry).
- Flexible categories (user-created, colour-coded, archivable; protected "Screen Time"
  system category; AI keyword auto-suggestion).
- Sleep mode (manual sun/moon **switch** at the top of the log sheet; courtesy "still
  sleeping?" notification, no data side effects).
- Routine builder & comparison; shared `HourTimeline` widget drives both Day View and Routine.
- Visualizations: daily pie (Dashboard), weekly stacked bar chart (History).
- Daily Intention → per-day to-do list (flagged task, swipe done/remove, roll-forward).
- Day View row-layout redesign (chat 6); Usage Stats over-counting fix (chat 4); Screen Time
  reconciliation rework (chat 5); Routine row redesign, AI outage fix, gradient fix, past-day
  logging (chat 7).

---

## 2. What was planned at the start of this session

The user's opening intent: **finish what's left** on the chat-7 backlog. Open items at
session start were the two owed device eyeballs (gradient, Routine screen), the AI-parse
hardening, a "bottom navbar issue," and the feature backlog (routine strip, sync,
onboarding, UI polish).

**Two things reframed early:**
- The "bottom navbar issue" is **not a bug** — it's part of the UI/gradient pass (nav labels
  unreadable against the brighter gradient bottom, plus a general look change the user wants).
- The user is handing the app to **friends for testing this week**, aiming for a green light
  before public launch. That changed priorities substantially (see §3.3).

**Order chosen by the user:** AI-parse hardening → Dashboard routine strip → sync →
onboarding → UI fixes. **Sync was then deliberately deferred** after discussion (see §3.3).

---

## 3. What THIS session built / fixed

### 3.1 AI-parse hardening — ✅ DONE (181 tests at completion)

**The problem** (a read-only diagnostic confirmed all three prior claims and found more):
the AI-parse submit loop discarded `insertRetroactive`'s return, had no try/catch, wasn't
transactional, popped the sheet unconditionally, didn't pass `avoidUsageDerived`, and a
single malformed AI entry killed the whole batch at parse time. Zero test coverage.

**Decisions locked with the user:**
1. On mid-batch failure, **keep going and report at the end** — but wrap **each entry in its
   own transaction** so no entry lands half-written.
2. **Match manual save**: pass `avoidUsageDerived: true` so AI entries slot *around*
   confirmed screen time instead of stacking on it.
3. Sheet stays open with counts unless everything landed; a **trimmed but written** entry
   counts as *added* with no message about the trim (matching manual `_save`).
4. One bad entry from the AI is **skipped**, not fatal to the batch.
5. The two other `insertRetroactive` return-discarding call sites
   (`settings_provider.dart` sleep auto-log, `carve_actions.dart`) were **left alone** —
   noted, out of scope.

**Phase 1 — `groq_service.dart`**
- `parseLogText` return type → `Future<({List<ParsedEntry> entries, int skipped})?>`.
  `null` = total failure; a valid empty array = `(entries: [], skipped: 0)`, not null.
- Per-entry tolerance: `DateTime.tryParse`, non-empty trimmed description, end strictly
  after start; bad items increment `skipped` instead of throwing. A non-String
  `suggestedCategory` → null, entry kept.
- **3-tier JSON extraction:** direct decode → first fenced block → **balanced-bracket scan**.
- **Prompt/model/HTTP untouched.**
- ⚠️ **The prompt was wrong and Claude Code was right to deviate:** the spec asked for the
  naive first-`[`/last-`]` substring as the final fallback *and* for a test proving prose
  containing a bracket parses correctly. Those are mutually exclusive. The balanced-bracket
  scan is a strict superset that satisfies both.
- Logic extracted to a pure top-level `parseEntriesFromRaw` so tests need no network.

**Phase 2 — `log_entry_sheet.dart` (`_ParseSheet`)**
- Writes delegated to `writeParsedEntries(db, entries, cats)`: each entry in its **own
  `db.transaction`**, `avoidUsageDerived: true`, per-entry try/catch. Buckets into
  `added` / `blocked` / `failed`.
- **Added entries are pruned from `_parsed`** after the loop, so tapping Confirm again only
  retries what didn't land. Nothing can be written twice.
- `_isConfirming` re-entrancy guard; Confirm and Re-try both disabled in flight.
- Outcome: all added → pop + `onDone()`, no message. Otherwise sheet **stays open** with
  exact counts (`Added $added of $total. $blocked already covered, $failed failed.` etc).
- Parse-stage `skipped` surfaced as a muted line above the review list.
- Testable seams: `writeParsedEntries` and `confirmMessageFor` are `@visibleForTesting`
  top-level functions, tested against a real in-memory Drift DB.

**Untested residue (user chose to leave it):** the `failed` bucket (no clean throw seam
without an injectable writer), plus widget-level pop/`onDone` and the re-entrancy guard.
Rationale: the prune already prevents the duplicate-write that the re-entrancy guard also
prevents, so the guards overlap and one is tested.

**Device eyeball still owed:** paste text covering an already-logged hour → sheet should stay
open with a count; paste text covering free hours → sheet closes silently.

### 3.2 Dashboard "Right now" routine strip — ✅ DONE (198 tests at completion)

**Spec locked — FULL REPLACE.** The Dashboard's `CurrentHourCard` used to show what the user
**logged** for the current moment. It now shows what their **routine** says for the current
hour, and **the logged readout is deleted from the Dashboard entirely.** The user chose this
over keeping a logged line alongside or beneath it.

- Current hour only, no "next up." **Display only**, no tap.
- Empty state: `— nothing planned`, styled identically to the old `— nothing logged`.
- **Overlap rule:** earliest `startHour` wins, **tiebreak on lowest `id`**. This matches Day
  View's existing collision rule (the Routine editor's lane-packing rule was *not* chosen).
  The id tiebreak is new — previously the winner was non-deterministic when two slots shared
  a `startHour`.
- Applicable-slot filter: `isActive && (dayOfWeek == weekday || dayOfWeek == 0)` — the Day
  View / DAO form.

**Phase 1** — new pure `lib/features/dashboard/current_slot_planner.dart` with
`slotForHour(...)` and `resolveSlotName(label, categoryName)` (the `label → category name →
"Unlabelled"` chain, previously inlined only in `routine_screen.dart`). Pure, no Flutter/Drift
— `resolveSlotName` takes the resolved category **name**, so the card does the id lookup.
13 tests, including a **determinism guard** that passes the same two slots in both orders and
asserts the same winner.

**Phase 2** — `CurrentHourCard` became a `ConsumerStatefulWidget`, watching
`allRoutineSlotsProvider` + `categoriesProvider`. **Two timers, deliberately:** `_LiveClock`
keeps its own per-minute timer for the clock string; the card body has a separate
minute-aligned timer that only `setState`s when the **hour value** changes. Merging them
would make the body rebuild 60× more than needed. Timer cancelled in `dispose`, all
`setState`s mounted-guarded.

**Test 4 is the load-bearing one:** with a log entry covering "now" and no routine slot, the
card shows `nothing planned` and does **not** show the entry's description — proving the
replace actually happened.

**Not automated:** the hour-rollover itself (the widget reads `DateTime.now()` directly;
making it injectable would mean restructuring for one test). User chose to leave it.

**Device eyeball owed:** an hour with a slot names it; an hour without says "nothing planned";
and — worth sitting with — whether losing the "have I logged this hour" signal from the
Dashboard bites during testing week.

### 3.3 Sync layer — ⏸️ DELIBERATELY DEFERRED (decision, not a build)

The user originally wanted full Supabase sync at #2 so friends would test "the version I'd
deploy." After laying out the trade-offs, the plan changed:

- **Sync is ~5 features** (accounts, push, pull, conflicts, local-data migration) and can
  lose data in ways local-only never does if rushed.
- **Friends don't need sync to give a green light.** Sync only shows itself on a second
  device or a reinstall.
- **Analytics does not need sync** — it rides the anonymous auth that already exists.
- Supabase supports **upgrading an anonymous user to a permanent one keeping the same user
  ID**, so nothing is thrown away by waiting.

**Accepted trade-off, explicitly:** during testing week, **a reinstall permanently loses that
person's data and it cannot be recovered.** The user will tell testers not to uninstall.

**Also established this session (asked directly):** a normal **app update does NOT lose
data** — SQLite lives in the app's private storage and survives. What loses data is
uninstall, "clear app data," or a new phone. Two caveats: **(a)** a schema change runs a
migration on users' phones, so any future migration must be tested against a *populated* DB,
not an empty one; **(b)** all builds handed out must use the **same signing key**, or Android
forces an uninstall and wipes everything. The user asked not to add a migration-safety step
to every prompt for now — raise it when the schema is actually touched.

### 3.4 Usage analytics (counters only) — ✅ DONE (215 tests at completion)

**Scope locked: COUNTERS ONLY.** No log entries, descriptions, or category names are pushed.
Consequence the user accepted: **no remote debugging of a friend's actual logs** (screenshots
instead), and **nothing of theirs sits in Supabase to claim** when accounts eventually land.

**Backend — built by hand in the Supabase dashboard, verified by curl:**
- Table `public.app_analytics`: `user_id uuid`, `date date`, `opens int`, `log_count int`,
  `has_routine bool`, `used_ai bool`, `updated_at`, PK `(user_id, date)`.
  **RLS ON with NO policies** = service-role only. The app never touches it directly.
- SQL function `public.record_analytics_ping(...)` — `security definer`, upserts on
  `(user_id, current_date)`, **increments `opens`** while **overwriting** the other three.
- Edge Function: **display name "analytics-ping" but the SLUG is `clever-action`** — the slug
  is what the URL uses. It validates the JWT and takes `user_id` **from the token, never the
  body**, then calls the SQL function with the service role.
- **Verify JWT is OFF** on that function (it does its own auth).

**Gotchas hit while wiring this up (all resolved, recorded so they aren't re-hit):**
- The Supabase gateway requires **BOTH** `apikey: <anon key>` **and**
  `Authorization: Bearer <token>`. A bearer-only request is rejected before the function runs.
- **`GroqService` sends only the bearer** and `groq-proxy` accepts it — so its header block
  **must not be copied** for analytics. Claude Code caught this and corrected the prompt.
- The dashboard auto-generated the slug `clever-action` and editing the display name did not
  change it.
- The first deploy silently didn't take — the function was still running the hello-world
  template, which surfaced as `Hello undefined!`.

**App side:**
- `AnalyticsService.pingIfDue()` in `lib/core/analytics/`, exposed via a plain `Provider`,
  fired **fire-and-forget from `DashboardScreen._onResume`** (which already runs on cold start
  and every resume — no new `WidgetsBindingObserver`).
- Guarded once per **calendar day** by the pure `shouldPing(lastPing, now)` in
  `analytics_guard.dart`.
- **No schema change:** the guard reuses the previously-dead `UserSettings.lastSyncedAt`
  column (a **`String?` holding ISO-8601**, not a DateTime — parse it; unparseable → treat as
  null → ping). The **used-AI flag lives in SharedPreferences** (`UsedAiStore`), set only on a
  **2xx** `GroqService` call, never on a throw or 429.
- Order: guard → token check (no session → return **without** writing `lastSyncedAt`, so it
  retries) → gather counters → POST with both headers → write `lastSyncedAt` **only on 2xx**.
  Every failure is swallowed with `debugPrint`; nothing reaches the user or blocks the UI.
- HTTP was fakeable **without restructuring**: `accessToken` and `postPing` are `@protected`
  seams a test subclass overrides, matching `_FakeNotificationService`.
- **Request body is exactly three keys** — `log_count`, `has_routine`, `used_ai` — and a test
  asserts the key set stays exactly those three, so it can't quietly grow.

**Device check owed:** run the app → a row appears in `app_analytics` with a real
`log_count`; close and reopen → **`opens` does NOT increase** (once-per-day guard).

### 3.5 First-run onboarding — ✅ DONE (226 tests at completion)

**Spec locked:** 5 full-screen swipeable cards, **skippable**, replayable later,
**explanation only** (no setup actions, no permissions, no account), seen-flag in
**SharedPreferences** (no schema change; a reinstall re-shows it, which is fine).

**The diagnostic's STEP 5 was the most valuable part of this session** — it checked each
planned claim against real code and found **two were wrong**:
1. *"Missed hours show up so you can fill them in later"* — **overstated.** They appear
   **only inside the log entry sheet**, labelled "UNLOGGED HOURS," as quick-picks. There is
   **no** Dashboard or Day View nudge. Copy reworded.
2. *"The app doesn't score you"* — **half wrong.** The day thumbs are user-only, but Day View
   **does** auto-grade routine adherence green/amber/red. Copy reworded to own this rather
   than contradict it.

**Final card copy (in `onboarding_screen.dart`, treat as locked unless the user changes it):**
1. **Log the hour that just ended** — ChronoPlan works backwards. At 6:45, you log what you
   did between 5 and 6. No planning ahead, no guessing. Just what actually happened.
2. **You can't log the future** — Only hours that have already passed. If you try to log
   ahead, the app will stop you. The current hour opens once it's underway.
3. **Missing hours is normal** — You won't catch every hour, and that's fine. Open the logger
   and any hours you haven't filled in show up as quick picks. Fill them whenever you like —
   yesterday, this morning, three days ago.
4. **Tell it when you're asleep** — There's a switch at the top of the logger with a sun and a
   moon. Flip it to the moon when you go to bed, back to the sun when you wake. It fills in
   that whole stretch for you.
5. **You decide how the day went** — Day View shows how close you got to your routine, in
   green, amber and red. That's just information. Whether it was a good day is your call, and
   yours only.

**Phase 1 — store + gate.** `SeenOnboardingStore` (clone of `UsedAiStore`, key
`seen_onboarding`) in `lib/core/onboarding/`. `main()` **awaits the flag before `runApp`** and
builds the router with the resolved initial location — **no `redirect`**, so the Dashboard
never paints first. `router.dart`'s `final router` became
`GoRouter createRouter({String initialLocation = '/'})`; `app.dart` now takes the router.
The **same store instance** is injected via `overrideWithValue` so startup and the app share
one cache. Failure path returns **false → onboarding shows** (better to show twice than never).

**Phase 2 — the screen.** `PageView.builder` of 5 pages + a hand-built dot indicator (no
packages — nothing like this existed in the app). Content renders **directly on the gradient,
not inside a `GlassCard`**, because `GlassCard`'s `GestureDetector` is `HitTestBehavior.opaque`
and would fight the horizontal drag. Skip on cards 1–4; "Get started" on the last. One
decorative accent icon per card was added (copy untouched) — **not yet eyeballed by the user.**
Replay row added to **Profile** (`_LinkTile` → `/onboarding`) — Settings has no navigating-row
pattern and About is static, so Profile was the natural home.

**Origin-return decision: `context.canPop()`**, not a query param. First run → onboarding is
the only route → `canPop()` false → `go('/')`. Opened from Profile via `push` → `canPop()`
true → `pop()` back to Profile. Works for both Skip and Get started; `markSeen()` is
idempotent so replay is harmless.

**Device check owed (tests can't prove it):** clear app data → launch → **no flash of the
Dashboard** before card 1.

---

## 4. Current state summary

| Area | State |
|---|---|
| Core logging, categories, sleep, routine, visualizations, to-do list | Built (prior sessions) |
| Day View + Routine row layouts, shared `HourTimeline` | Built (chats 6–7) |
| AI (Groq via proxy, `openai/gpt-oss-20b`) | Working |
| **AI-parse hardening** | ✅ Built this session — device eyeball owed |
| **Dashboard "Right now" routine strip (full replace)** | ✅ Built this session — device eyeball owed |
| **Usage analytics (counters only), backend + app** | ✅ Built this session — device check owed |
| **First-run onboarding** | ✅ Built this session — device check owed |
| Supabase sync / accounts | ⏸️ Deliberately deferred until after testing week |
| Gradient polish + nav labels + general UI | ❌ Open (next queued item) |

- **Tests: 226 passing. `flutter analyze` clean. schemaVersion unchanged at 7.**

**Files created this session:** `lib/features/dashboard/current_slot_planner.dart`,
`lib/core/analytics/analytics_guard.dart`, `lib/core/analytics/analytics_service.dart`,
`lib/core/analytics/used_ai_store.dart`, `lib/core/onboarding/seen_onboarding_store.dart`,
`lib/features/onboarding/onboarding_screen.dart`, plus tests
`test/parse_log_text_test.dart`, `test/parse_confirm_test.dart`,
`test/current_slot_planner_test.dart`, `test/current_hour_card_test.dart`,
`test/analytics_guard_test.dart`, `test/log_entries_count_test.dart`,
`test/analytics_service_test.dart`, `test/analytics_ping_call_site_test.dart`,
`test/onboarding_gate_test.dart`, `test/seen_onboarding_store_failure_test.dart`,
`test/onboarding_screen_test.dart`.

**Files changed:** `lib/core/ai/groq_service.dart`,
`lib/features/log_entry/log_entry_sheet.dart`,
`lib/features/dashboard/widgets/current_hour_card.dart`,
`lib/features/dashboard/dashboard_screen.dart`,
`lib/core/database/daos/log_entries_dao.dart` (`countAll`),
`lib/core/database/daos/routine_slots_dao.dart` (`countAll`),
`lib/providers/settings_provider.dart`, `lib/config/supabase_config.dart`,
`lib/features/profile/profile_screen.dart`, `lib/router.dart`, `lib/app.dart`,
`lib/main.dart`.

---

## 5. Before handing the build to friends (checklist)

1. **Remove `debugPrint('TOKEN: ...')` from `main.dart`** if still present (added to grab a
   JWT for testing the Edge Function). It prints a session token on every launch.
2. **Use the same signing key for every build.** A different key forces an uninstall, which
   wipes their data.
3. **Tell testers not to uninstall** — no account backup yet, a reinstall loses everything.
4. **Keep the Supabase project awake.** Free tier pauses after ~1 week idle, which now takes
   down **both AI and analytics** (this is what killed all AI in chat 7).
5. Complete the four device checks listed in §6.

---

## 6. Still to build / fix (backlog)

### A. Device checks owed from this session (no code, just eyeballs)
- **AI parse:** paste text covering an already-logged hour → sheet stays open with a count;
  paste text covering free hours → sheet closes silently.
- **Routine strip:** an hour with a slot names it; an hour without says "nothing planned";
  and whether losing the Dashboard's "have I logged this hour" signal is missed.
- **Analytics:** a row appears in `app_analytics` with a real `log_count`; reopening the app
  does **not** increment `opens`.
- **Onboarding:** clear app data → launch → no Dashboard flash; all 5 cards readable; skip
  then reopen (doesn't return); Profile replay returns to Profile. Also eyeball the
  decorative accent icons that were added per card.
- **Still owed from chat 7:** the gradient 4-clock eyeball (~08:00/14:00/18:00/23:00) and the
  Routine screen eyeball. User said "will do later."

### B. Next queued item — UI fixes (the user's #4)
- **Gradient polish, as one pass:**
  1. `accentForHour` doesn't track time of day — the accent (e.g. the + button) stays blue
     while the background is orange.
  2. Top-left corner of the gradient is too dark / not smooth.
  3. **Bottom-nav *labels* hard to read** against the brighter gradient bottom (icons are
     fine). ⚠️ **This is the entire "bottom navbar issue"** — it is a UI change, not a bug.
- **General look change** the user wants across the app (not yet enumerated — ask for
  specifics).

### C. Deferred until after testing week
- **Supabase sync layer / accounts.** Email + password preferred, **optional** (app must stay
  usable with no account), anonymous → permanent upgrade so the same user ID is kept, and
  existing local data pushed up and preserved. Goals stated: **backup** and **the user seeing
  tester data**. ⚠️ This one **will** touch the schema — test the migration against a
  **populated** DB before shipping.

### D. Known bugs / inconsistencies found but deliberately NOT fixed
- **Debrief sends deactivated routine slots to the AI.** `debrief_screen.dart` filters slots
  by day **without** the `isActive` check, unlike Day View and the DAO. Turning a slot off
  still feeds it to the coach. Small fix, real bug.
- **The Dashboard decides "today" three different ways** (raw `DateTime.now()` for the header,
  `selectedDateProvider` for entries) and **ignores `currentDayProvider`**, the
  across-midnight-safe provider built in chat 3. Same class of bug that once made tasks
  vanish at midnight.
- **`appOpenCount` is not "app opens"** — it increments on *every* resume via `_onResume`,
  including a post-frame cold-start prime. It over-counts. (The analytics ping does not depend
  on it.) Still read by `UsageAccessCard`'s `appOpenCount < 2` gate.
- **Two more `insertRetroactive` call sites discard the return** —
  `settings_provider.dart` (sleep auto-log on wake) and `carve_actions.dart`. The sleep one
  can silently lose a sleep entry if the window is already covered.
- **Failed anonymous sign-in is never retried in-session** — only on the next cold start. AI
  and analytics both inherit this.

### E. Deferred Routine interaction bugs (from chat 7, unchanged)
- Edit can't change a slot's start hour or weekday.
- Copy-to-days accumulates duplicate rows (no dedupe).
- No overlap prevention (no uniqueness constraint on routine slots).
- Delete is instant swipe with no confirm/undo.
- Optional: restore an "every-day slot" cue (the dimming/caption dropped in chat 7).

### F. Smaller polish (carried)
- Screen Time card wording.
- Weekly-insight AI prompt is missing routine data.
- AI persona consistency across debrief / weekly insight / category suggestion.
- App-name labeling/filtering robustness (Usage Stats).
- **AI resilience:** move the model name out of the app `const` into a Supabase secret the
  proxy reads, and **surface the real AI error** instead of the generic "couldn't reach AI"
  (chat 7's outage was three stacked backend problems hidden behind one message).

### G. Narrow Screen Time edges / dropped
- Only one app reconciled per hour.
- The 11 PM–midnight hour never gets a suggestion/carve.
- Screen Time "honesty layer" (Phase 3) — dropped in chat 5.

---

## 7. Working conventions (how this user likes to work — FOLLOW THESE)

- **Diagnose before fixing.** Every fix/feature starts with a **read-only diagnostic** prompt
  that reads real code and reports (call-sites, schema, reactivity), changing nothing. These
  are load-bearing, not ceremony — this session they **overturned two onboarding claims that
  would have shipped as lies**, corrected a wrong header assumption in the analytics prompt,
  and found that the Dashboard's "right now" element was about logs, not routine.
- **Ask permission before issuing any Claude Code prompt.** Describe what it will do, get a
  yes, then give it.
- **Spec-first / contract-first.** Lock the full behavioural spec (including edge cases)
  before writing code. Play it back for confirmation when dense.
- **Phased builds with verification gates.** Break work into phases; **STOP** at each gate,
  report, confirm before continuing. Include explicit verification checklists and, for
  regressions, a test that provably fails-before / passes-after (this session: the
  bracket-in-prose parse test, the double-write 5a/5b pair, the same-`startHour` determinism
  guard, the "logged text is gone" replace proof).
- **Every prompt is a complete pasteable markdown block** with a **STEP 0 reality-check gate**,
  an explicit **"Do NOT"** section, verification steps, and a **STOP-if-mismatch** rule.
- **Pure-function-first for logic.** Flutter/Drift-free files with their own unit tests
  (`current_slot_planner.dart`, `analytics_guard.dart` join `hour_row_planner.dart` and
  `routine_overlay_planner.dart`); keep the widget layer thin.
- **Modular; reuse existing patterns** rather than inventing parallel ones. This session:
  `SeenOnboardingStore` clones `UsedAiStore`; the analytics fake copies
  `_FakeNotificationService`; the count queries copy `IntentionTasksDao`'s.
- **Reactivity discipline.** Entries, missed-hours, counts, routine data are Drift `.watch()`
  streams + Riverpod. If something doesn't update, **find the non-reactive source and report
  it — don't paper over it with `provider.invalidate`.**
- **When a prompt's assumption is wrong, say so rather than fitting the code to it.** This
  happened three times this session and each time the correction was right.
- **When a test needs a seam that would mean restructuring, report it instead of
  refactoring** — decide together. (The parse `failed` bucket and the hour-rollover test were
  both left untested by explicit choice.)
- **Reply in simpler, plain language.** The user moves fast once trade-offs are clearly laid
  out, and prefers to **be asked rather than have things assumed**.
- **Device eyeball is part of every gate.** Tests prove logic; the user's phone is the final
  check, especially for anything visual.

---

## 8. Infrastructure notes

- **Supabase:** anonymous auth, established unconditionally in `main()` before `runApp`
  (failure is swallowed with a `debugPrint`, never retried in-session). `ai_usage` enforces
  the 100 req/user/day quota server-side. **Free tier auto-pauses after ~1 week idle → AI
  *and* analytics both go down.**
- **Edge Function `groq-proxy`:** validates JWT, increments `ai_usage`, 429s over quota,
  forwards to Groq, streams when `stream: true`. Accepts a **bearer-only** request.
- **Edge Function `clever-action`** (display name "analytics-ping"): validates JWT, takes
  `user_id` from the token, calls `record_analytics_ping` with the service role. Requires
  **both** `apikey` and `Authorization` headers. Verify JWT **off**.
- **Groq:** no time-based key expiry — a dead key was revoked (401 `invalid_api_key`); Groq
  **retires model slugs** periodically (404 `model_not_found`). Rotate via
  `supabase secrets set GROQ_API_KEY=...` (no redeploy).
- **Dev environment (Windows + physical Android):** `flutter run -d android` with USB
  debugging. PowerShell: plain `curl` is aliased — use `Invoke-RestMethod` or `curl.exe`.
  Gotchas: delete any stray `web/` folder (breaks sqlite3 FFI); short non-OneDrive path;
  Gradle `org.gradle.parallel=false`, `kotlin.incremental=false`; Defender exclusions.
  Bottom sheets need `useRootNavigator: true`.
- **Test harness patterns:** in-memory Drift (`NativeDatabase.memory()`) with the sqlite3 DLL
  override; `ProviderScope` + `overrideWithValue` with real subclasses as fakes (**no mocking
  package anywhere**); `SharedPreferences.setMockInitialValues`; `GoRouter` +
  `MaterialApp.router` mini-routers; bounded pumps (the now-line `Timer.periodic` means
  `pumpAndSettle` never settles); careful teardown before `db.close()`.
- **Security habit worth keeping:** during this session a session JWT was pasted into chat
  while debugging. Low-stakes here (anonymous, ~1h expiry), but the same reflex with the
  **service role key** or the **Groq key** would be a real incident. Copy the error, not the
  credential.

---

## 9. Data-integrity note (carried)

Carves/suggestions write to the log on user confirmation, so any carve confirmed while the old
Usage Stats bugs were live may have corrupted real hours. Fixes correct future behaviour but
don't repair already-written data — worth auditing affected days by hand if anything looks off.
