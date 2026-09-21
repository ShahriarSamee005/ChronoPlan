# ChronoPlan — Session Handoff (Chat 10)

A handoff for a fresh chat to pick up ChronoPlan development with full context.
ChronoPlan is a **Flutter Android app** for hourly retrospective time-logging, routine
comparison, and AI-driven productivity coaching.

**This document supersedes the chat 9 handoff**, which carried two stale backlog entries
forward from chat 3 (see §4). Test count at the end of this session: **312 passing**,
`flutter analyze` clean, `flutter build apk --release` succeeding.

---

## 1. What the app is

**Core concept**
- Tracks how the day is spent in hourly increments, compares against a user-defined ideal
  routine, and provides AI coaching on the gap. **The user — not the app — decides whether a
  day was good** (thumbs up/down; no app-generated verdict or score).
- Fundamental log model: at any moment past the top of an hour, the user logs *the hour that
  just ended*. No future logging. Missed hours surface as retroactive opportunities, never as
  "lateness."
- Every entry is an ordinary, fully-editable retrospective record. Nothing is immovable.

**Target users:** mostly students. This shapes product decisions — e.g. Screen Time should
surface time-sink apps (browsers, YouTube) rather than every installed app.

**Built (prior sessions)**
- Time logging (hourly / custom-interval reminders, contextual quotes, missed-hours strip,
  free-text + one category tag per entry).
- Flexible categories (user-created, colour-coded, archivable; protected system categories;
  AI keyword auto-suggestion). 11 seeded defaults.
- Sleep mode (manual sun/moon toggle only).
- Routine builder & comparison (day-at-a-time vertical timeline, copy-to-days; green/amber/red
  ghost-block edges in Day View).
- Visualizations: daily pie (Dashboard), weekly stacked bar chart (History, fl_chart).
- Daily intention → to-do list (flagged task, soft/hard delete, roll-forward-on-load carry-over).
- Onboarding (5 cards), analytics ping.
- AI via **Groq + Llama 3.1 8b Instant**, proxied through a Supabase Edge Function
  (`groq-proxy`), Supabase anonymous auth, 100 req/user/day quota. Selectable coach persona
  (Drill Sergeant / Friendly Coach / Neutral Analyst). Graceful offline fallback.
- Screen Time / Usage Stats: hand-rolled Kotlin `queryEvents` method channel, session
  reconstruction, hourly suggestions with carve/reconcile.

**Tech stack**
- Flutter (Android first), Riverpod, Drift (SQLite, offline-first, schemaVersion 7),
  Supabase (anon auth + Edge Functions + Postgres), flutter_local_notifications 17.2.4,
  fl_chart, flutter_timezone 5.1.0.
- Android: hand-rolled Kotlin `queryEvents` method channel (the `app_usage` package only
  returns daily aggregates, unusable for per-hour).

**App identity — LOCKED**
- `applicationId` / `namespace` = **`dev.chronoplan.app`**
- Home-screen label = **`ChronoPlan`**
- Kotlin source at `android/app/src/main/kotlin/dev/chronoplan/app/`
- **The MethodChannel name strings were deliberately left as
  `com.example.chronoplan/usage_stats`, `com.example.chronoplan/usage_permission`, and
  `com.example.chronoplan/notification_permission`.** Channel names are arbitrary
  identifiers that only need to match Kotlin↔Dart. **Do not "fix" those `com.example` greps.**
- Changing `applicationId` again would force every tester to uninstall and lose all data
  (no sync yet).

**UI direction**
- Glassmorphism, dark-mode-first. Semi-transparent `GlassCard`s with blur + rounded corners.
- Time-of-day dynamic background gradient. Manrope typography (now bundled). Colourblind-aware
  category palette.
- Bottom nav: Dashboard | Day View | [+ Log] | Routine | History. `AppShell` hosts the nav as a
  persistent `ShellRoute`; full-page routes push on top of it.

---

## 2. Working conventions (how this user likes to work)

These were consistent and effective across ten sessions. A new chat should follow them.

- **Diagnose before fixing.** Never make blind changes. Before any build, run a **read-only
  diagnostic prompt** (changes nothing, reports call-sites/schema/reactivity) so the fix is
  built against real code, not assumptions. This session the diagnostics repeatedly proved
  the stated theory wrong — see §5.
- **Ask permission before issuing any Claude Code prompt.**
- **Spec-first / contract-first.** Lock the full behavioural spec (including edge cases)
  *before* writing code. Play it back for confirmation when dense.
- **Phased builds with verification gates.** Break work into phases; STOP at each gate,
  report, and confirm before continuing.
- **Prompts as complete pasteable markdown blocks** with explicit "Do NOT" sections and
  verification steps.
- **Tests must be load-bearing.** Write the test first, *prove it fails*, then fix. This
  session caught three tests that passed whether or not the code worked.
- **Modular architecture; reuse existing patterns** rather than inventing parallel ones.
- The user moves fast once trade-offs are clearly laid out. Reply in plain language.
- **Always ask, don't assume.**

**Reactivity discipline:** missed-hours, Screen Time suggestions, task card/sheet, and counts
are all backed by Drift `.watch()` streams + Riverpod. Deletes/edits must flow through
reactively. If something doesn't update, **find the non-reactive source and report it — don't
paper over it with `provider.invalidate`.**

---

## 3. What this session built

### 3a. App icon — ✅ COMPLETE

Root cause: **the icon config had never pointed at the right artwork.** `pubspec.yaml` named
an old logo file for both `image_path` and `adaptive_icon_foreground`, and
`adaptive_icon_background` was the flat colour `#BFD5F5` — so the gradient had never been in
the icon at all. Compounding it, the artwork filled its whole canvas, and Android masks
launcher icons to roughly the central two-thirds.

Fix:
- New artwork at 1024×1024: `icon_foreground.png` (hourglass scaled into the safe zone),
  `icon_background.png` (gradient, resized from 1254), `icon_legacy.png` (flat composite for
  Android 8.0 and below).
- `adaptive_icon_background` now a **file path**, so it generates a real drawable, not a
  `@color`.
- **`adaptive_icon_foreground_inset: 0`** — `flutter_launcher_icons` 0.14 defaults to 16%,
  which would have shrunk already-correctly-sized art a second time.
- Verified: `mipmap-anydpi-v26/ic_launcher.xml` background is `@drawable/ic_launcher_background`.

### 3b. Splash screen — ✅ COMPLETE

Two constraints that shaped everything:
- **Android 12+ clips the splash image to a circle.** The artwork must fit inside it. Spec:
  a 1152×1152 image with all content inside a **768px-diameter circle**.
- **`icon_background_color` must NOT be set.** Setting it selects Android's *smaller* 240dp
  splash-icon variant instead of the 288dp one, shrinking the logo ~17% for no benefit
  (the circle would be the same colour as the screen).

Fix:
- `splash_android12.png` — 1152×1152, hourglass + CHRONOPLAN wordmark padded into the circle.
- Top-level `image: splash.png` added. Before this, **Android 11 and below showed a blank
  blue screen with no logo at all.**
- Ran `flutter_native_splash:remove` before `create` to clear stale generated drawables.
- The Flutter-side `SplashGate` overlay was **deleted** (widget, wiring, and 5 tests). Native
  handles everything.

### 3c. Manrope bundled locally — ✅ COMPLETE

The app used the `google_fonts` package, which **downloads the font at runtime**. Offline, the
unhandled exception killed the first frame. Every fresh install needed internet on first launch.

Fix:
- Weights bundled: **400, 500, 600, 800**. Note: the app renders **w800 (ExtraBold)** and
  **no w700** — bundling Bold instead would have silently dropped the largest heading a weight.
- Files produced as genuine static instances from the real Manrope variable font via
  `fontTools.varLib.instancer`. Verified per file: **`fvar` table absent**,
  `OS/2.usWeightClass` matching. A variable font would render every weight identically.
- `GoogleFonts.manropeTextTheme(base)` → `base.textTheme.apply(fontFamily: 'Manrope')`.
- Four calls that relied on `GoogleFonts.manrope()`'s implicit w400 now set
  `fontWeight: FontWeight.w400` **explicitly**, since a bare `TextStyle(fontFamily:)` leaves
  weight null and inherits.
- `google_fonts` removed from `pubspec.yaml`.
- Known minor difference: `GoogleFonts` also set a `fontFamilyFallback`; `apply` does not.
  Only matters for glyphs Manrope lacks.

### 3d. Asset trim — ✅ COMPLETE

`assets: - assets/branding/` shipped the whole folder. Audit found **zero runtime asset
loads** anywhere in `lib/` — the Dashboard "app icon" is a `Text` title, About and onboarding
use vector `Icon`s.

- All nine top-level branding files moved into `assets/branding/source/` (not shipped).
- Two duplicates deleted only after **SHA-256** comparison, not matching byte counts.
- The `assets:` key removed from `pubspec.yaml` entirely.
- Both generator configs repointed at `assets/branding/source/`.
- **6,422,322 bytes (~6.4 MB) no longer in the APK**, proven by `unzip -l` showing zero
  branding entries. The debug APK size delta was meaningless (~170 MB is dominated by
  `kernel_blob.bin`).

⚠️ **`assets/branding/source/` is now the only copy of the branding artwork.** The generators
point there. Don't clean it out thinking it's junk.

### 3e. Dashboard breakdown card — ✅ COMPLETE

The user reported the pie chart overlapping its legend and asked for padding. **There was
already a 12px gap.** The real bug: `radius: 70` + `centerSpaceRadius: 34` made a 208px-wide
donut in a ~165px slot. fl_chart doesn't clip, so it silently painted over the gap and into
the legend. On touch the radius grew to 82 → 232px wide, spilling 33px each side.

Fix:
- `pieRadiusFor(chartWidth)` — a pure, testable top-level function deriving the radius from
  the measured slot, reserving `kPieTouchGrowth` (12) plus 2px safety, clamped [8, 120].
- `LayoutBuilder` measures the real slot using the same 3:2 flex split and 12px gap.
- The fixed `SizedBox(height: 190)` removed: **the card now grows to fit the legend** (chosen
  behaviour "A1"). At 9+ categories the old fixed height overflowed — and a default install
  seeds 11.
- Consequence: the donut is now ~137px where it was drawn at 208px. Correct, but smaller. If
  it ever reads too small, widen the chart's share of the row (3:2 → 2:1); the radius follows
  automatically.

### 3f. History "Top Category" — ✅ COMPLETE

Sleep won every week by definition, making the headline uninformative.

- New pure function `topCategoryFor(entries, cats)` excludes **the Sleep category** and
  **uncategorized entries** (`categoryId == null`).
- **Sleep is matched on `isSystem && name == 'Sleep'`.** Filtering on `isSystem` alone would
  be wrong — **Screen Time is also `isSystem: true`** and must stay eligible. There is a test
  specifically guarding this (case 6).
- The name is safe to key on because Sleep is a system category and the UI blocks renaming,
  archiving, and even saving a colour change. Hardcoding the id would be fragile (auto-increment,
  no explicit seed).
- Headline only. Sleep still counts in the chart, the Total, the vs-Last-Week delta,
  drill-downs, and the AI weekly insight (verified unchanged).
- Fallback reuses the existing `None` string; the empty-week en-dash `–` (U+2013) is untouched.

### 3g. Log entry sheet — ✅ COMPLETE

Two problems, and the second depended on the first.

**Height cap.** The sheet rendered at **800 of 800 logical pixels — the entire screen, top
edge at y=0.** That put it in Android's notification-shade gesture zone, which is why dragging
down sometimes pulled the system shade.
- `kLogSheetMaxHeightFraction = 0.85`, applied via a `ConstrainedBox` **inside the widget**, so
  all four call sites are covered by one change (they pass identical args but there is no shared
  opener).
- The `ConstrainedBox` sits *inside* the existing keyboard-inset `Padding`, so the sheet still
  lifts above the keyboard — the one intended exception to the cap.

**Pinned Save button.** It was the last child inside the single `SingleChildScrollView`, laid
out **300px below the sheet's bottom edge** — genuinely unreachable without scrolling.
- Restructured to `Column` → `Flexible(SingleChildScrollView(content))` → Save as a sibling.
- **`Flexible`, not `Expanded`.** Expanded is a tight fit and would force the sheet to always
  be 85% tall, breaking the short-content case. Flexible shrink-wraps when short and fills when
  tall.
- Intended: the keyboard covers the Save button while typing. Not a bug.

### 3h. Screen Time — fragmentation and rounding — ✅ COMPLETE

Two defects destroying usage data before any threshold was applied.

**Sessions were shredded.** Android emits FOREGROUND/BACKGROUND per *Activity*, not per app.
`_reconstructSessions` closed the running session on every FOREGROUND event even for the *same*
package, so in-app navigation (Reels, story viewers, comment sheets, in-app browsers) split one
session into dozens of 1–12 second fragments. Nothing merged them.

**Each fragment was floored to whole minutes before summing.** `minutesOverlapping` returned
`ms ~/ 60000` per session, so the hour total was a *sum of floors*. Twelve 10-second fragments
= 120 real seconds = **0 credited minutes**.

Together, a fragmenting app could burn 20 real minutes and register zero.

Fix:
- `millisOverlapping` is now the accumulation primitive. `_bucketMinutes` sums **milliseconds**
  and floors **once** at the end.
- **The same defect was found and fixed in two more places:** `getTodayUsage()` (so the
  "Today's Usage" card was undercounting too) and `getDebugSnapshot()`'s stage-C minutes
  (which would otherwise have contradicted the pipeline it exists to inspect).
- `_mergeAdjacentSessions` — a **post-pass**, not a change to the event walk, whose correctness
  is pinned by 21 tests. Merges consecutive same-package sessions when the gap is
  `_kMergeGapSeconds = 5` or less. A new `_Session.barrier` flag is set at screen-off/keyguard
  suspend and device shutdown, and blocks merging across a real interruption.
- One existing test was rewritten: it had asserted the *pre-fix split* (same package, two
  foregrounds → two sessions) as correct behaviour. Its real guarantee (no double-counting,
  total 15) is still asserted.

**Note:** the 10-minute threshold was already applied to an app's **summed total per hour**,
not per session. A clean 5 + break + 5 always qualified. The rounding bug was what killed
fragmented apps.

### 3i. Notifications — three phases + two root-cause fixes — ✅ COMPLETE

#### Phase 1 — permission card

**`POST_NOTIFICATIONS` was never requested.** It was declared in the manifest and
`NotificationService.requestPermission()` existed and was correct — but had **zero call sites**.
With `targetSdk 36`, the permission starts denied on Android 13+, no dialog is ever shown, and
every scheduled alarm is silently dropped by the OS. **The app's core loop had never worked on
any modern phone.**

- New `NotificationPermissionCard` on the Dashboard. Appears from the **second resume onward**
  (`appOpenCount >= 2`), matching the usage-access card. **No ✕ and no dismissal** — it hides
  only when permission is granted (chosen behaviour "C").
- New `notificationPermissionProvider` backed by `areNotificationsEnabled()`, invalidated in
  `_onResume` and again right after the button runs (the runtime dialog doesn't reliably produce
  a lifecycle round-trip).
- **Android's ask limit:** the system dialog stops appearing after two denials, after which
  `requestNotificationsPermission()` returns false without showing anything. The plugin exposes
  no `shouldShowRequestPermissionRationale` equivalent, so the button asks, and if that neither
  granted nor evidently showed a dialog, it opens the app's notification settings page on the
  same tap.
- New Kotlin channel + `openNotificationSettings()`. `ACTION_APP_NOTIFICATION_SETTINGS` is
  API 26+, so there's an app-details fallback for minSdk 24.

#### Phase 2 — quiet hours + sleep suppression

- `quiet_hours.dart`: `kQuietStartHour = 1` (inclusive), `kQuietEndHour = 9` (exclusive).
  00:00 still fires; 09:00 still fires.
- **Quiet hours are implemented by NOT scheduling, not by skipping a fire.** When an alarm
  fires, no Dart runs at all — the plugin's native receiver posts it from data saved at
  schedule time. Fortunately hourly mode registers 24 independent alarms (ids `300 + h`), so
  hours 1–8 are excluded simply by not registering them. 24 − 8 = **16 alarms**.
- **Sleep-toggle suppression was also a bug fix.** `setSleepMode` never touched the notification
  service, and `cancelAll()` lived *inside* the scheduling methods that the
  `if (!sleepModeActive)` guard skipped — so turning the toggle on left already-armed alarms
  firing right through sleep mode.
- New `cancelReminders()` walks **only** ids 300–323 and 100–147. **Never `cancelAll()` on the
  sleep path** — that would take the weekly reflection (998) and inactivity check (999) with it.
- New `rescheduleReminders()` re-arms on toggle-off, respecting mode, interval, and quiet hours.

#### The R8 / ProGuard fix — release-only crash

Release builds threw:

```
java.lang.IllegalStateException: TypeToken must be created with a type argument:
new TypeToken<...>() {}; When using code shrinkers (ProGuard, R8, ...) make sure
that generic signatures are preserved.
```

Chain: R8 strips the `Signature` attribute → the plugin's Gson-based
`loadScheduledNotifications()` throws → `cancelNotification()` throws → **`_onResume` dies at
its first `await`, before any scheduling runs** → zero alarms are ever registered. Confirmed by
`adb shell dumpsys alarm` showing no alarms for the package.

**Debug builds are unaffected — R8 only runs on release.** So every tester build was broken and
no amount of debug testing would have revealed it.

- New `android/app/proguard-rules.pro` following the plugin README's documented Gson rules.
  **`-keepattributes Signature` is the actual fix.**
- One rule beyond upstream: `-keep class com.dexterous.flutterlocalnotifications.models.** { *; }`
  — AGP 9.0.1 makes R8 full mode mandatory, which can delete reflectively-read fields outright
  and rename enum constants, silently corrupting the persisted schedule rather than throwing.
- Minification stays **ON**. Note: the Flutter Gradle plugin already sets `isMinifyEnabled`,
  `isShrinkResources`, and **auto-appends `android/app/proguard-rules.pro` when the file exists** —
  so creating the file alone would have fixed it. The explicit `proguardFiles` line is redundant
  but documents intent.
- The notification icon is `@mipmap/ic_launcher`, which `resources.txt` confirms is reachable
  from the manifest, so resource shrinking keeps it. No `keep.xml` needed.

#### The `tz.local` fix

`init()` called `tz.initializeTimeZones()` but nothing ever called `tz.setLocalLocation`, so
**`tz.local` was UTC** and every `tz.TZDateTime` was a UTC time wearing a local label.

Three consequences:
1. The **weekly reflection** intended Sunday 20:00 but scheduled Sunday 20:00 UTC = **Monday
   02:00** on a UTC+6 device. Confirmed in `dumpsys`. That prompt had never arrived on a Sunday
   evening.
2. **Notification quotes picked their pool by UTC hour**, so morning quotes arrived in the
   afternoon.
3. **Quiet hours needed a workaround** — `firesInQuietHours()` routes through the epoch
   specifically to sidestep this.

Fix:
- `flutter_timezone: ^5.1.0` added. New `device_timezone.dart` with a three-tier fallback:
  platform IANA name → any zone at the device's current UTC offset → `tz.UTC`. Nothing throws,
  nothing leaves the app unscheduled.
- A named IANA zone was chosen over a raw offset because it carries its own DST transition rules.
- **DST-safe day arithmetic:** the roll-to-tomorrow branch was `fire.add(Duration(days: 1))`,
  which adds 24 *absolute* hours and lands on `h±1:00` across a DST transition. Replaced with a
  rebuild on `now.day + 1`. Same for the reflection's Sunday walk. **Decision: keep it.**
- **What the bug actually did:** the reminder *count* and *local times* were never wrong. Because
  `firesInQuietHours` judged on the device clock via the epoch, the right 16 alarms fired at the
  right local times — but under **ids rotated by 6** ({303…318} instead of {300, 309…323}). Only
  the weekly reflection, which had no epoch workaround, visibly misfired. That's why `dumpsys`
  looked plausible before.
- `firesInQuietHours()` is unchanged. Its claim that it "stays correct if `tz.local` is ever
  initialised to the device zone" is now **verified by a test**, not assumed.

#### Phase 3 — wake notification

- **Id 997**, clear of 300–323, 100–147, 998, 999.
- Armed when `setSleepMode(active: true)` runs, for `sleepModeStartedAt + 8 hours`.
- **Quiet hours win absolutely:** if the 8-hour mark lands in 01:00–08:59 local, it defers to
  09:00 local that same morning. Reuses `isQuietHour` / `kQuietEndHour` — no second rule.
- Cancelled on `setSleepMode(active: false)`.
- Copy: title `Wakey wakey ☀️`, body *"Your bed made a compelling argument. Tap to log the
  night."*
- New payload `kNotifPayloadWakeUp`, handled by opening the log entry sheet. **Not**
  `kNotifPayloadConfirmSleep`, which is handled nowhere.
- **A defect found while wiring it:** the first deferral computed 09:00 on `tz.local`'s calendar
  day while `firesInQuietHours` judges on the *device* clock. Those agree normally but not on the
  UTC fallback path — and then the deferral could resolve to a time already past, and
  `zonedSchedule` throws a past date straight out of `setSleepMode`, breaking the toggle. Second
  trap: `TZDateTime.toLocal()` means `tz.local`, **not** the device zone. Fixed by going through
  the epoch exactly as `firesInQuietHours` does.

---

## 4. Corrections to the record

Three things were wrong in the chat 9 handoff and were corrected this session:

1. **Usage Stats over-counting was already fixed in chat 4.** The root cause everyone kept
   repeating ("sessions aren't closed when the screen turns off") was *wrong*. The real cause was
   an "assumed-open-since-start" branch that back-dated stray unmatched BACKGROUND events to
   midnight, manufacturing 20-hour sessions. Fixed, with invariant guards clamping per-hour totals
   at 60 minutes, and `usage_phantom_background_test.dart` written failing-first.
2. **Suggestion/manual-log overlap was already fixed in chat 5** — the `isUsageDerived` provenance
   column, `planCarve()` splitting rather than replacing, and `insertRetroactive`'s
   `avoidUsageDerived` flag. Chats 6, 7 and 8 all listed both as done; chat 9 copied chat 3's text
   forward without re-checking, and it survived three handoffs unquestioned.
3. **The "which tests skip" mystery is solved.** The total is constant; the pass/skip split moves
   with the wall clock. Two files use runtime `markTestSkipped` hour-guards
   (`pending_reconciliation_count_test.dart`, `usage_suggestion_confirm_test.dart`). Nothing is
   silently disabled.

**Lesson for the next handoff: re-verify carried-forward "known blockers" against the code
before repeating them.**

---

## 5. Hard-won environment and device knowledge

**Diagnostics repeatedly beat theories this session.** In five separate cases the stated
hypothesis was wrong and a read-only diagnostic found the real cause:
the icon (config never pointed at the art, not a sizing issue), the pie chart (overspill, not
missing padding), Sleep in the headline (`isSystem` would have wrongly excluded Screen Time),
the screen-time threshold (already per-hour-summed, not per-session), and the notification
failure (R8, not ColorOS or exact-alarm permissions).

**Tests that pass for the wrong reason.** Three were caught:
- The phase-2 test asserting skipped ids {300, 309…323} set `tz.local` by hand and never
  exercised the production path.
- The defensive `cancel(_kWakeId)` was guarded by nothing — alarms are keyed by id and same-id
  replacement makes duplicates impossible, so "exactly one pending" passed either way.
- `sliceByHourForTest` hardcodes `userFacing: true`, so the `userFacing` filter is structurally
  untestable from Dart. One provider test asserts Chrome *produces* a suggestion, the exact
  opposite of on-device behaviour.
The habit that works: write the test, **prove it fails**, then fix.

**Windows / PowerShell**
- `adb` is not on PATH. It lives at
  `C:\Users\MARUF\AppData\Local\Android\sdk\platform-tools\adb.exe`. Add for a session:
  `$env:Path += ";C:\Users\MARUF\AppData\Local\Android\sdk\platform-tools"`.
- PowerShell has no `grep`. Use `Select-String -Pattern "..." -Context 2,6`.
- Device serial is `5c204cf5`; model `RMX3521` (Realme, ColorOS, Android 14).

**`dumpsys alarm` double-counts.** Each alarm is listed in **both** the batch section and the
pending list. Count unique `Alarm{<hash>}` objects, not grep lines. A raw `grep -c` inflated
17 alarms to 27 twice before being caught.

**ColorOS attaches a delivery window.** Even with `exactAllowReason=policy_permission`
confirming the `SCHEDULE_EXACT_ALARM` grant, Realme attaches up to a **one-hour** delivery
window (naming `app_standby`, `battery_saver`, `tare`). A 14:00 reminder can arrive at 14:59.
The window shrinks as the alarm nears. **Not a code defect** — but every Realme, Oppo, Xiaomi
and vivo tester will hit it. Tell testers to exempt ChronoPlan from battery optimisation.

**New Kotlin needs `flutter build apk`.** `flutter analyze` and `flutter test` never compile
Kotlin. Always build after touching `MainActivity.kt`.

**`flutter_timezone` emits a KGP warning:** *"Future versions of Flutter will fail to build if
your app uses plugins that apply Kotlin Gradle Plugin (KGP)."* Builds fine today. **Decision:
note it, no action.** The maintainer will almost certainly fix it before it matters; this
warning is appearing across the whole ecosystem.

**Dev environment (Windows + Android):** always `flutter run -d android` with a physical device
+ USB debugging. Delete any stray `web/` folder (breaks sqlite3 FFI); keep the project on a
short non-OneDrive path; Gradle `org.gradle.parallel=false`, `kotlin.incremental=false`; add
Defender exclusions. Bottom sheets need `useRootNavigator: true`.

---

## 6. Still to build / fix

### 🔴 Blocks handing the app to testers

1. **`Supabase.initialize()` is unbounded.** It does a token refresh over the network on any
   launch with a saved session. The sign-in right after it *was* bounded; this was left open.
   On a bad connection (rather than none) it can sit waiting. Small fix.
2. **Signing key.** Every build handed out must use the same key — a different one forces an
   uninstall and wipes the tester's data. Confirm a release keystore exists rather than shipping
   debug builds (the debug key is machine-specific).

### 🟠 Performance — user-reported

3. **The app feels slow and laggy.** A debug run showed `Skipped 154 frames` and
   `Davey! duration=2598ms` — beyond normal debug overhead. **First step: check whether it
   persists in `flutter run --release`.** Candidates if it does: every `GlassCard` runs a
   backdrop blur (5–6 stacked on the Dashboard, more in the log sheet); the usage-stats
   reconstruction runs on the main thread on resume and now has an extra merge pass; Drift
   `.watch()` streams fanning out on writes; the time-of-day gradient rebuilding.
   Measure with profiling rather than guessing from that list.

### 🟡 Screen Time — remaining work

4. **The `userFacing` filter rejects preinstalled apps.** Kotlin's `resolveAppInfo` checks
   `ApplicationInfo.FLAG_SYSTEM`, which means "shipped in the system image", **not** "is a
   system utility". So **Chrome, YouTube, Gmail, Maps, Photos, Drive, Messages, Play Store,
   and OEM browsers/galleries are all classed as not-user-facing.** The debug view's
   "launcher/system/own app" wording is misleading — no launcher-intent check exists anywhere.
   **User's chosen approach:** an **allowlist** of time-sink apps (browsers, YouTube, and
   similar) rather than a general launcher-icon test, on the reasoning that students waste time
   on browsers and YouTube but not on Maps or Gmail. **Plus** resolving the HOME intent at
   runtime to exclude whatever launcher the user has (never a hardcoded launcher name).
   Trade-off the user accepted: the allowlist needs occasional maintenance — a Samsung user
   browsing in Samsung Internet gets nothing until it's added.
   Manifest `<queries>` already declares the LAUNCHER intent correctly, so package visibility
   is not the problem.
5. **Screen Time accounting view.** The user asked "how do we test this entire thing" after
   seeing 59m of Chess detected but only 16m suggested. The answer: for any app, show where the
   day's minutes went — *detected 59m, suggested 16m, 22m below threshold across five hours,
   12m in hours that already had entries, 9m in the current hour.* Every minute accounted for
   with a reason. Turns "the app is inconsistent" into a screen you read.
   Note some divergence is by design: the "Today's Usage" card has **no threshold and no hour
   bucketing**, while suggestions require 10+ minutes within a single clock hour and must
   survive the current-hour exclusion, dismissed hours, and the overlap check.
6. **Replay a captured real day as a test fixture.** Every existing test uses hand-written
   synthetic events. Add a debug export that dumps a full day of raw events, save one real day,
   and run the whole pipeline over it asserting per-hour per-app totals. The pipeline's inputs
   are messy in ways nobody invents by hand.
7. **An overlapping entry suppresses an hour's suggestion.** `hasEntry` is bare interval
   overlap with no origin filter, so a 3-minute manual entry at 14:00–14:03 kills the whole
   14:00 hour, and a 09:00–17:00 "work" block kills every hour it touches. Pre-existing,
   possibly intended, worth revisiting.
8. **Zero test coverage of the threshold and the `userFacing` filter.** See §5.
9. **Usage Stats Phase 3 — the "honesty layer."** AI coaching on logged-vs-actual
   discrepancies. **This is the app's headline idea and it is now unblocked** — it was parked
   behind the over-counting bug, which turns out to have been fixed in chat 4.

### 🟡 Real bugs, still open

10. Debrief sends **deactivated** routine slots to the AI. Small fix.
11. Dashboard decides "today" three different ways and **ignores `currentDayProvider`** — the
    same bug class that once made tasks vanish at midnight.
12. `appOpenCount` over-counts (it counts *resumes*, so a background/foreground round-trip
    within one session bumps it).
13. Two `insertRetroactive` call sites discard the return value — the sleep auto-log can
    silently lose an entry.
14. A failed anonymous sign-in is never retried within a session.

### 🟡 Routine screen interaction gaps

15. Editing a slot can't change its start hour or weekday.
16. Copy-to-days duplicates rows.
17. No overlap prevention between slots.
18. Delete is an instant swipe with no confirm or undo.
19. Optional cue for every-day slots.

### 🟠 Code traps and dead code

20. `app_theme.dart` pins every `ElevatedButton` foreground to white. Three call sites were
    patched individually; the trap remains for the next accent-filled button.
21. `ElevatedButton` and `FilledButton` behave **oppositely** here — five accent-filled
    `FilledButton`s work correctly *by accident* and would flip to broken the moment a
    `filledButtonTheme` with a white foreground is added.
22. **`SleepModeCard` is dead code** — defined but never instantiated. The live sleep toggle is
    only reachable through the log entry sheet. That's a discoverability question for the UI
    pass, and it also means the wake notification's tap target had to be the sheet.
23. **Dead columns:** `lastSleepPromptDate`, `lastIntentionPromptDate`, `gentleReminderTimes` —
    all declared, zero reads, zero writes. `showSleepConfirmation()` and `showIntentionPrompt()`
    are defined but never called.
24. **The "still sleeping?" notification is half-built.** Its body promises "your sleep will be
    logged automatically", but its `confirm_sleep` payload is handled nowhere. Tapping it opens
    the app and does nothing. *The user has said repeatedly to leave this alone.*
25. Some widget tests pass on tree presence alone and would still pass if the widget were
    invisible. The splash tests had exactly that flaw before a pixel test was added.
26. **No timezone-change receiver.** Nothing reschedules on `TIMEZONE_CHANGED`; it corrects
    itself on the next app resume.
27. Possible later cleanup: `firesInQuietHours()` collapses to `isQuietHour(fireAt.hour)` now
    that `tz.local` is correct — but only for `fireAt` built in `tz.local`, and the UTC fallback
    keeps the epoch route safer. **Recommendation: keep it as-is.**
28. The mode rule (`'custom'` or `'strict'` → custom interval) now exists in two places:
    `rescheduleReminders` and the inline check in `_onResume`. Merge when convenient.

### 🟢 Larger, deferred

29. **Supabase sync layer.** Anonymous → permanent account upgrade, push local rows,
    multi-device sync. `user_id` already reserved on every table. Will touch the schema.
    Deferred until after testing week.
30. **Screen-by-screen UI pass.** Two screens were done this session (Dashboard breakdown, log
    sheet) and both turned out to have real bugs behind the cosmetic complaint. Worth continuing.
31. **AI polish.** Persona consistency across debrief / weekly insight / category suggestion;
    weekly insight prompt missing routine data; Screen Time card wording; move the AI model name
    into a Supabase secret; surface the real AI error.

---

## 7. Data-integrity note (carried forward)

Because carves/suggestions write to the log on user confirmation, any carve confirmed while the
Usage Stats bugs were live may have corrupted real hours (e.g. a full slot converted to Screen
Time). Worth auditing affected days by hand; fixes correct future behaviour but don't repair
already-written data.

---

## 8. Infrastructure notes

- **Supabase:** Singapore region, anonymous auth. `ai_usage` table enforces the 100 req/user/day
  quota server-side; RLS "users read own usage" (writes via Edge Function service_role).
  **Free tier pauses the project after ~1 week of inactivity — keep the dashboard active or
  expect AI downtime.**
- **Edge Function `groq-proxy`:** validates JWT, increments `ai_usage`, 429s over quota, forwards
  to Groq (`GROQ_API_KEY` from Supabase secrets), streams when `stream: true`.
- **Groq free tier** shared across users; cliff ~14,400 req/day total — monitor `ai_usage` as the
  user base grows.
- **Key rotation:** Groq key via `supabase secrets set GROQ_API_KEY=...` (no redeploy). Supabase
  anon key embedded in app (safe to expose; rotating needs an app update).
- `compileSdk = 36`, `minSdk = 24`, `targetSdk = 36`. AGP 9.0.1.

---

## 9. Non-code rules before handing out builds

- **Every build must use the same signing key.** A different key forces an uninstall and wipes
  the tester's data.
- **Tell testers not to uninstall.** There is no backup until sync lands.
- **Tell testers to exempt ChronoPlan from battery optimisation**, especially on Realme, Oppo,
  Xiaomi and vivo. Otherwise reminders arrive up to an hour late.
- **Test notifications on a RELEASE build, not debug.** R8 only runs on release, and that
  difference hid a total notification failure for an entire session.
- **Uninstall completely before reinstalling** when testing icon or splash changes. Android
  caches launcher icons hard.
- Keep the Supabase dashboard active — the free tier pauses after ~1 week of inactivity.
