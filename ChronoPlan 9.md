# ChronoPlan — Session Handoff (Chat 9)

A handoff document for a fresh chat to pick up ChronoPlan development with full context.
ChronoPlan is a **Flutter Android app** for hourly retrospective time-logging, routine
comparison, and AI-driven productivity coaching.

This session: cleared the pre-handoff checklist, did the UI/gradient pass, rebuilt the nav
bar as a floating pill, and then spent a long and painful stretch on app icon + splash
screen — which ended by uncovering a **real launch-blocking bug** that has nothing to do
with either.

---

## 1. Context carried in from previous chats (chats 1–8)

**Core concept**
- Tracks how the day is spent in hourly increments, compares against a user-defined ideal
  routine, and provides AI coaching on the gap. **The user — not the app — decides whether
  a day was good** (thumbs up/down). The app only auto-grades *routine adherence*
  (green/amber/red), never the day itself.
- Fundamental log model: at any moment past the top of an hour, the user logs *the hour
  that just ended*. No future logging. Missed hours surface as retroactive opportunities,
  never as "lateness."
- Every entry is an ordinary, fully-editable retrospective record. Nothing is immovable.

**Tech stack**
- Flutter (Android first), Riverpod, Drift (SQLite, offline-first, **schemaVersion 7**),
  Supabase (anon auth + Edge Functions + Postgres), flutter_local_notifications, fl_chart,
  go_router.
- Android usage: hand-rolled Kotlin `queryEvents` method channel.
- AI via **Groq + Llama 3.1 8b Instant**, proxied through a Supabase Edge Function
  (`groq-proxy`), Supabase anonymous auth, 100 req/user/day quota. Selectable coach persona.

**UI direction**
- Glassmorphism, dark-mode-first. Semi-transparent `GlassCard`s with blur + rounded corners.
- Time-of-day dynamic background gradient. Manrope typography. Colourblind-aware category
  palette.
- Bottom nav: Dashboard | Day View | [+ Log] | Routine | History. `AppShell` hosts the nav
  as a persistent `ShellRoute`; full-page routes push on top of it.

**Built before this session**
- Time logging, flexible categories, sleep mode, routine builder & comparison,
  visualizations (daily pie, weekly stacked bar), AI debrief/insights, Day View swipe-to-
  delete, daily intention → to-do list, across-midnight provider fix, AI parse hardening,
  Dashboard "right now" routine strip, analytics counters, first-run onboarding.

**Known blocker carried in (still parked)**
- **Usage Stats over-counting.** Per-hour usage badly inflated (~45h/day). Root cause:
  foreground sessions aren't closed when the screen turns off. The whole Usage Stats
  feature and the Phase 3 "honesty layer" are parked behind this.

---

## 2. What this session did

### 2a. Pre-handoff cleanup — ✅ COMPLETE
- Read-only diagnostic found the `debugPrint('TOKEN: ...')` from chat 8 **was already
  gone** — nothing to remove. Zero credential-logging anywhere in `lib/` or Kotlin.
- Baseline confirmed: `flutter analyze` clean, 226 tests (219 passing + 7 skipped),
  schemaVersion 7.
- All owed device checks from chats 7 and 8 passed: AI parse, routine strip, analytics row,
  onboarding no-flash, gradient at four clock times, Routine screen.
- **Note:** the onboarding check wipes app data. The user's own logs/routine/categories
  were wiped and need rebuilding for the Day View comparison to mean anything on device.

### 2b. UI Phase 1 — gradients + neutral accents — ✅ COMPLETE

**Two findings that overturned the chat 8 backlog:**

1. **`accentForHour` was never broken.** The backlog said it "doesn't track time of day."
   It already returned four distinct accents on the same hour boundaries. The real problem:
   chat 7 rewrote all twelve gradient colours but left the four accents untouched, so the
   pairings went stale. Midday = orange background + sky-blue accent, exactly the reported
   symptom.
2. **Darkness wasn't the gradient problem — *range* was.** Night has the darkest top stop
   of all four (`0xFF0A1330`) and reads fine, because it runs navy → steel blue, a narrow
   band. The other three ran near-black → near-white. Fix was compressing each toward its
   middle colour, not lightening the top.

**Changes (`app_colors.dart`):**
- `_morning`: `0xFF4A2A5E`, `0xFFA83F6E`, `0xFFD97A55`
- `_midday`: `0xFF6E3F1C`, `0xFFC56A1F`, `0xFFD9932F`
- `_evening`: `0xFF25455F`, `0xFF2F7CAD`, `0xFF6BA7C9`
- `_night`: **untouched** (verified byte-identical)
- `accentForHour` → near-white, faintly tinted: `0xFFFFF3EA` / `0xFFFFF6E8` /
  `0xFFEFF6FA` / `0xFFEDF0F7`
- New `onAccentForHour(hour)` → dark foreground for content drawn on the accent:
  `0xFF4A2A5E` / `0xFF6E3F1C` / `0xFF25455F` / `0xFF0A1330`
- New `sleepTrack = Color(0xFF7986CB)` — deliberately NOT the accent (the sleep switch
  thumb is white and would vanish on a near-white track). Same colour as before, so the
  switches look unchanged.

**The audit gate paid for itself.** Before editing anything, the prompt required classifying
every `accentForHour` call site as FILL (breaks on near-white) or SAFE. It found **5 breaks
beyond the known "+" button** and stopped without editing:
- 3 `ElevatedButton`s (Routine save, onboarding "Get started", log-entry Save) — break
  because `app_theme.dart:88` pins every ElevatedButton's foreground to white
- 2 `Switch`es with hard-coded white thumbs on the night accent track
- Plus two hard-coded white `CircularProgressIndicator`s inside the Save buttons (a button
  `foregroundColor` does not reach them)

All fixed. New `test/accent_palette_test.dart` guards luminance and contrast gaps so this
pairing cannot silently regress again.

**Verified on device: everything looked right.**

### 2c. UI Phase 2 — floating island nav pill — ✅ COMPLETE

`Scaffold` already had `extendBody: true` and the bar already blurred at sigma 20, so this
was margins, radius and fill — not a rework.

- New `NavBarMetrics` class in `app_shell.dart`: `height 64`, `bottomMargin 12`,
  `horizontalMargin 16`, `radius 32`, `contentGap 16`, and
  `clearance(context)` = height + bottomMargin + contentGap + safe-area inset.
- `_GlassNavBar` → `Padding` → `ClipRRect` → `BackdropFilter` → `Container`.
  Fill `0x14FFFFFF` → `0x1FFFFFFF`. Top-only border → uniform `Border.all` + `borderRadius`.
- **Uniform border matters:** a `Container` with `borderRadius` and a non-uniform
  `Border(...)` trips a debug-only assert that red-screens on device but passes in release.
- Icons, labels, four destinations, and the "+" button all unchanged.
- `HourTimeline` got an optional `bottomPadding` param (default 100) so `core/theme` doesn't
  import `features/shell`. Dashboard, History, Day View and Routine now pass
  `NavBarMetrics.clearance(context)`.

**STEP 1 of that prompt caught a stale premise.** An earlier diagnostic reported Routine's
scroll as a `SingleChildScrollView` with 32px bottom padding. It's actually the slot-editing
bottom sheet. Routine's hour rows live in `HourTimeline`'s own `ListView`. Padding the
wrong widget would have added dead space in a sheet and left the real rows hidden.

**Verified on device: everything looked right.**

### 2d. App icon + splash screen — ⚠️ PARTIALLY DONE, STILL BROKEN

This consumed most of the session and produced a lot of churn. See §3 for the root cause
and §4 for exactly what's left.

**What got built:**
- `flutter_launcher_icons` and `flutter_native_splash` added to `dev_dependencies`.
- `flutter_native_splash.yaml` created. Now a plain `color: "#BFD5F5"` with an `android_12:`
  block using the same colour for both background and icon background (so no visible box).
- `lib/features/splash/splash_gate.dart` — `SplashGate`, a Flutter-side splash overlay.
- `lib/app.dart` — `MaterialApp.router` `builder:` wraps the router child in `SplashGate`.
- Asset reorganisation: generator inputs moved to `assets/branding/source/` (NOT declared
  in `pubspec.yaml`, so they stop shipping in the APK). Runtime files stay directly in
  `assets/branding/`.
- `test/splash_gate_test.dart` — 5 tests, including a real pixel-visibility assertion added
  after the original 4 proved blind.

**Key platform constraint learned the hard way:**
> **Android 12+ ignores the custom splash image entirely.** The platform draws its own
> splash: a background colour plus the icon clipped to a circle. A wordmark under the logo
> is **not possible natively** on Android 12+. That is the entire reason `SplashGate` exists.

The user repeatedly screenshotted the *native* splash and reported "the typography isn't
showing." Diagnostic proof: the screenshot background sampled `(190,213,245)` — flat, top
to bottom. `SplashGate`'s gradient runs `#D3E2F8` → `#4883DE` and would visibly deepen.

**`SplashGate` spec (locked, working, verified correct in tests):**
- Base layer solid `#BFD5F5`, identical to native, so frame one shows no jump.
- Gradient + content fade in over 400ms. `LinearGradient` topLeft→bottomRight,
  stops `[0.0, 1.0]`, colours `#D3E2F8` → `#4883DE`.
- Content: single merged `assets/branding/splash.png` at `width: 210`, `BoxFit.contain`.
  No colour filter — the wordmark is white by design.
- `minimumVisible = 1200ms`, then `fadeOut = 350ms`, then removed from the tree entirely.
- Wrapped in `IgnorePointer`. Overlays the router child — **never decides what that child
  is**, so `main()`'s pre-`runApp` onboarding gate is untouched.

### 2e. Startup sign-in timeout — ✅ COMPLETE (real bug, found by accident)

`main()` awaited `signInAnonymously()` before `runApp` with **no timeout**. On a hung
request this blocked the main thread ~28 seconds (`Skipped 1718 frames`). The existing
`try/catch` handled a *failure* but not a *hang*.

- New `kSignInTimeout = Duration(seconds: 4)` and `@visibleForTesting boundedSignIn(...)`
  in `main.dart`. One bounded attempt, distinct log messages for timeout vs error, `runApp`
  always reached. No retry, no fire-and-forget, still before `runApp`.
- New `test/startup_signin_timeout_test.dart` — hang / throw / success.
- **Confirmed working on device: launch went from ~28s to fast.**

---

## 3. 🔴 THE ACTIVE BLOCKER — read this first

**The phone had no internet. `Network is unreachable, errno = 101`.**

The device log revealed the actual cause of everything:

```
Unhandled Exception: Exception: Failed to load font with url
https://fonts.gstatic.com/s/a/1ddee...ttf: ClientException with SocketException:
Connection failed (OS Error: Network is unreachable, errno = 101)
#0 _httpFetchFontAndSaveToDevice (package:google_fonts/src/google_fonts_base.dart:268:5)
```

**The app downloads Manrope from Google Fonts at runtime via the `google_fonts` package.**
With no network the download throws an **unhandled exception** during the first build, the
widget tree dies mid-paint, and the isolate stops driving frames and timers. `SplashGate`
mounts, builds once at fade-in value 0.0, and freezes there — so only the flat `#BFD5F5`
base is ever visible.

This also explains the Supabase `AuthRetryableFetchException` (same lack of network — the
Supabase project itself is **Healthy**, verified in the dashboard).

Why tests never caught it: `flutter test` uses a fallback font and never touches the network.

**Two actions:**
1. **Immediate:** get the phone online and re-run. Expect the splash to work with no code
   change.
2. **Must fix before testers:** bundle Manrope as a local asset instead of fetching it at
   runtime. A runtime font download means the app breaks on first launch for anyone offline
   — plane, bad mobile data, anywhere. Also makes launches faster.

---

## 4. Still to build / fix

### 🔴 Immediate — blocks handing the app to testers

1. **Bundle Manrope locally.** Remove the runtime `google_fonts` network fetch. Unhandled
   exception on any offline launch. See §3.
2. **Icon config has NEVER been applied.** `pubspec.yaml` still reads:
   ```yaml
   adaptive_icon_background: "#BFD5F5"
   adaptive_icon_foreground: "assets/branding/Chronoplan logo 5.png"
   ```
   It has never pointed at `icon_foreground.png` / `icon_background.png`. An earlier prompt
   halted at a canvas-size gate and never reached the config step. **This is why the icon
   has looked identical every single time.**
   - Android insets adaptive foregrounds to the central ~66%. Feeding the full artwork in
     is what produces the shrunken-in-a-box look.
   - `icon_foreground.png` is 1024×1024, content 568×600 — **passes** the ≤620px safe zone.
   - `icon_background.png` is **1254×1254 — needs re-exporting at 1024×1024** to match.
     Mismatched canvases scale the layers relative to each other.
   - Then: point both fields at those files, regenerate, and confirm
     `mipmap-anydpi-v26/ic_launcher.xml` references a background **drawable**, not
     `@color/ic_launcher_background`.
3. **Bound `Supabase.initialize()`.** Diagnostic found it attempts a **token refresh over
   the network** on any launch with a persisted session. We bounded the sign-in but left an
   unbounded network call directly in front of it. Same class of hang.
   (`NotificationService.init()` was audited and is local-only — platform channels, no
   network. Lower concern.)

### 🟠 Cleanup accumulated this session

4. `app_theme.dart:88` pins every `ElevatedButton` foreground to white. Three call sites
   were patched individually; the trap remains for the next accent-filled button.
5. `ElevatedButton` and `FilledButton` behave **oppositely** in this app — identical-looking
   code gives white foreground on one, black `onPrimary` on the other. Five accent-filled
   `FilledButton`s work correctly today **by accident**, and would flip to broken the moment
   a `filledButtonTheme` with a white foreground is added.
6. **Nobody has ever named which tests skip on wall-clock hour.** The count has come back
   7, 1, 0, and 7 again across this session, always explained as time-dependent skips, never
   verified. Tests that silently stop running are worth identifying once.
7. Splash tests were originally blind — all 4 passed on tree presence and would have passed
   with the overlay invisible for its whole life. A pixel-visibility test was added. Worth
   checking other widget suites for the same blindness.
8. `assets/branding/` — confirm only runtime files ship. `Chronoplan logo 5 icon.png` may
   now be unused depending on how item 2 lands.

### 🟡 Real bugs found earlier, still open

9. Debrief sends **deactivated** routine slots to the AI. Small fix.
10. Dashboard decides "today" three different ways and **ignores `currentDayProvider`** —
    same class of bug that once made tasks vanish at midnight.
11. `appOpenCount` over-counts.
12. Two `insertRetroactive` call sites discard the return value — sleep auto-log can
    silently lose an entry.
13. Failed anonymous sign-in is never retried within a session.

### 🟡 Routine screen interaction gaps

14. Editing a slot can't change its start hour or weekday.
15. Copy-to-days duplicates rows.
16. No overlap prevention between slots.
17. Delete is an instant swipe with no confirm or undo.
18. Optional cue for every-day slots.

### 🟢 Larger, deferred

19. **Usage Stats over-counting** (HIGH — the long-standing blocker). Reconstruct a full-day
    foreground timeline from `queryEvents`, then slice into hour buckets. Close each session
    at the earliest of: next `ACTIVITY_PAUSED`/`MOVE_TO_BACKGROUND` for that package, next
    `ACTIVITY_RESUMED` for a *different* package, screen-off / `SCREEN_NON_INTERACTIVE`,
    keyguard/lock, `DEVICE_SHUTDOWN`, or timeline end. **Do not** close on
    `ACTIVITY_STOPPED` alone. Invariants: no session or per-app-per-hour total exceeds the
    bucket; sessions never overlap; no negative/zero durations. A raw-events +
    reconstructed-sessions debug view already exists.
20. **Suggestion/manual-log overlap.** Accepting a Screen Time suggestion then manually
    logging the same hour produces overlapping entries. A prior full-reconciliation rewrite
    **broke missed-hours suggestions and was reverted** — retry must be tightly scoped.
21. **Supabase sync layer.** Anonymous → permanent account upgrade, push local rows,
    multi-device sync. `user_id` already reserved on every table. Will touch the schema.
    Deferred until after testing week.
22. Screen Time card wording; weekly insight prompt missing routine data; AI persona
    consistency across debrief / weekly insight / category suggestion; app-name labelling
    robustness; move the AI model name into a Supabase secret; surface the real AI error.
23. Usage Stats Phase 3 "honesty layer" — **blocked on #19**.
24. Screen-by-screen UI pass — the user wanted this once the shared layer was sorted. The
    shared layer is now done.

---

## 5. Non-code rules before handing out builds

- **Every build must use the same signing key.** A different key forces an uninstall and
  wipes the tester's data.
- **Tell testers not to uninstall.** There is no backup until sync lands.
- **Uninstall completely before reinstalling** when testing icon or splash changes. Android
  caches launcher icons hard; a plain reinstall or hot restart keeps showing the old one.
- Keep the Supabase dashboard active — the free tier pauses after ~1 week of inactivity.
  (Checked this session: **Healthy**, not paused.)

---

## 6. Working conventions (how this user likes to work)

- **Diagnose before fixing.** Never make blind changes. Run a **read-only diagnostic prompt**
  (changes nothing, reports call-sites/schema/reactivity) so the fix is built against real
  code. This session, diagnostics repeatedly overturned assumptions — `accentForHour` wasn't
  broken, Routine's scroll wasn't where an earlier report said, the token print was already
  gone, and the splash freeze was a font download.
- **Ask permission before issuing any Claude Code prompt.**
- **Spec-first / contract-first.** Lock the full behavioural spec including edge cases
  *before* writing code. Play the spec back for confirmation when it's dense.
- **Phased builds with verification gates.** Break work into phases; STOP at each gate,
  report, and confirm before continuing.
- **Gates that stop the build are worth their weight.** The accent audit gate found 5 unknown
  breaks. The Routine scroll gate caught a stale premise. Both would have shipped bugs.
- **Prompts as complete pasteable markdown blocks** with explicit "Do NOT" sections and
  verification steps.
- **Modular architecture; reuse existing patterns** rather than inventing parallel ones.
- **Reply in simple, plain language.** Ask rather than assume.
- The user moves fast once trade-offs are clearly laid out.

**Reactivity discipline:** missed-hours, Screen Time suggestions, task card/sheet, and counts
are all backed by Drift `.watch()` streams + Riverpod. If something doesn't update, **find
the non-reactive source and report it — don't paper over it with `provider.invalidate`.**

**Lesson from this session's icon/splash struggle:** when a change repeatedly fails to appear
on device, **get a device-side signal (instrumented `debugPrint` + full `flutter run` log)
before writing another fix.** Five prompts were spent on theories. The log answered it in one
run. Also: read the *whole* log — the answer was an unhandled exception 200 lines in.

---

## 7. Infrastructure notes

- **Supabase:** Singapore region, anonymous auth. `ai_usage` enforces the 100 req/user/day
  quota server-side. Project URL `https://eiyodbqepoylpcxwjsxu.supabase.co`. **Free tier
  pauses after ~1 week of inactivity.**
- **Edge Function `groq-proxy`:** validates JWT, increments `ai_usage`, 429s over quota,
  forwards to Groq, streams when `stream: true`.
- **Groq free tier** shared across users; cliff ~14,400 req/day total.
- **Key rotation:** Groq key via `supabase secrets set GROQ_API_KEY=...` (no redeploy).
- `groq_service.dart:285` prints the SSE response body on a bad status — useful for
  diagnosing AI outages, deliberately kept.

**Dev environment (Windows + Android):** `flutter run -d android` with a physical device
(RMX3521, Android 14) over USB. Known gotchas: delete stray `web/` folder (breaks sqlite3
FFI); keep the project on a short non-OneDrive path; Gradle `org.gradle.parallel=false`,
`kotlin.incremental=false`; add Defender exclusions. Bottom sheets need
`useRootNavigator: true`.

**Project root:** `F:\Flutter_code\Flutter_projects\chronoplan`

---

## 8. Current baseline

| Metric | Value |
|---|---|
| `flutter analyze` | Clean |
| `flutter test` | 237 passing + 7 skipped (counts vary — see §4 item 6) |
| schemaVersion | 7 |
| Gradients / accents | ✅ Done, verified on device |
| Floating nav pill | ✅ Done, verified on device |
| Sign-in timeout | ✅ Done, verified on device |
| App icon | ❌ Config never applied — see §4 item 2 |
| Flutter splash | ⚠️ Code correct, blocked by the font crash — see §3 |
| Manrope font | ❌ Downloaded at runtime, crashes offline — see §3 |
