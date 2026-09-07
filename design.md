# ChronoPlan — Design Reference

A description of how ChronoPlan looks, complete enough for another chat to build a visual
mockup of the app without access to the codebase.

> **Read this first.** Everything below marked ✅ is quoted from or directly confirmed against
> the real source. Everything marked ⚠️ **GAP** is a value I could not confirm and must be
> filled in from the code before building anything colour-accurate. **Do not invent hex
> values for the GAP items** — §11 has a copy-paste prompt that extracts them all.

---

## 1. The one-line description

A dark, glassmorphic Android app whose entire background is a **time-of-day gradient** that
changes through the day, with **semi-transparent frosted cards** floating on top of it and
**Manrope** type throughout.

---

## 2. Overall style

- **Dark-mode first.** There is no light theme.
- **Glassmorphism.** Every content block is a translucent, blurred, rounded card sitting on
  the gradient — never an opaque panel.
- **The gradient is the background of almost every screen**, not a decoration. Cards are
  translucent *so the gradient shows through them*. This is the single most important thing
  to get right in a mockup: nothing is on a flat dark grey.
- **No borders-as-structure.** Separation comes from the frosted fill and soft rounding, not
  from dividers or outlines.
- Rounded everything. The default card radius is 20.
- Icon style is Material **`_rounded`** variants (`wb_sunny_rounded`, `bedtime_rounded`,
  `thumb_up_rounded`, `settings_outlined` etc.) — soft, not sharp.

---

## 3. The time-of-day gradient (the defining feature)

✅ Provided by `TimeGradientBackground`, a widget that wraps a screen's body:

```dart
body: TimeGradientBackground(child: SafeArea(...))
```

✅ Confirmed behaviour:
- It reads `DateTime.now().hour` and picks a palette via `AppColors.gradientForHour(hour)`.
- It renders an `AnimatedContainer`, so the change between palettes **animates**.
- It re-arms a `Timer` at each hour boundary to update itself.
- **Direction: `topLeft → bottomRight`.** Index 0 of the palette is the **top**. There is no
  reversal.
- **3 colours per palette.**
- Screens that opt in: Dashboard, Day View, Settings, About, Profile, Debrief, Onboarding.

✅ The four palettes and their hour ranges:

| Palette | Hours | Described as |
|---|---|---|
| Morning | 5–10 | orange-pink |
| Midday | 11–16 | orange |
| Evening | 17–20 | light blue |
| Night | 21–4 | deep blue |

✅ Each palette runs **dark at the top → bright at the bottom**.

⚠️ **GAP:** the 12 actual hex values (3 per palette) live in `lib/core/theme/app_colors.dart`.
They were deliberately rewritten in chat 7 to be **vivid and clearly distinct** — an earlier
version was "all navy" and that was treated as a bug. A test
(`test/gradient_palette_test.dart`) enforces that the four palettes are **pairwise distinct**.
So when mocking: make the four backgrounds obviously different from each other, and make each
one saturated rather than muted.

✅ There is also an **accent colour per hour**, `AppColors.accentForHour(hour)`. Used for the
onboarding active dot and other accent bits.

⚠️ **Known open issue, relevant to a mockup:** `accentForHour` does **not** currently track
time of day properly — the accent stays blue while the background is orange, so the **+ log
button clashes with the background**. If you're mocking the *intended* design, make the accent
harmonise with the background. If you're mocking the *current* state, it doesn't.

⚠️ **Two more known gradient flaws** (unfixed, listed here so a mockup can choose to show the
fixed or current state): the **top-left corner reads as too dark / not smooth**, and the
**bottom-nav labels wash out** against the brightened bottom of the gradient.

---

## 4. `GlassCard` — the core building block

✅ The exact constructor:

```dart
const GlassCard({
  super.key,
  required this.child,
  this.borderRadius = 20,     // double, feeds BorderRadius.circular()
  this.opacity = 0.12,        // double
  this.blurSigma = 10,
  this.padding,
  this.borderColor,
  this.fillColor,
  this.onTap,
  this.width,
  this.height,
});
```

✅ How it renders:
- Fill is `fillColor ?? Colors.white.withValues(alpha: opacity)` — so a **white overlay at
  12% opacity** by default. **If `fillColor` is set, `opacity` is ignored entirely.**
- A **backdrop blur** with sigma 10 behind the fill. This is what makes the gradient behind it
  read as frosted rather than simply tinted.
- Rounded corners at `borderRadius` (default 20).
- An optional 1px-ish border via `borderColor` — used sparingly and faintly.
- Its `GestureDetector` uses `HitTestBehavior.opaque` **even when `onTap` is null**, so a
  `GlassCard` swallows hit-tests from anything beneath or around it. (This is why the
  onboarding cards are *not* wrapped in one — it would eat the swipe.)

✅ Common opacity variants seen in real use:
- `0.12` — default, standard content card
- `0.08` — the Profile navigation rows (`_LinkTile`), i.e. a lighter, more recessive card

**For a mockup:** a white fill at 8–12% alpha over the gradient, blurred, corner radius 20.
Not a grey box.

---

## 5. Typography

✅ **Manrope**, via `GoogleFonts.manropeTextTheme`, with these theme overrides in
`app_theme.dart`:

| Style | Weight / size | Notes |
|---|---|---|
| `displayLarge` | w800 / 32 | |
| `titleLarge` | w600 / 20 | |
| `titleMedium` | w600 / 16 | |
| `bodyLarge` | — / 16 | |
| `bodyMedium` | — / 14 | |
| `labelSmall` | w500 / 11 | letterSpacing 0.6 |

✅ **Important:** most screens **hardcode `TextStyle(...)` inline** rather than pulling theme
styles. So the theme table above is the baseline, but the real observed conventions are:

| Role | Actual style used |
|---|---|
| Screen / sheet title | 20–21, **w700–w800** |
| Big display name (About) | **28 / w800** |
| Onboarding card heading | **26 / w800**, white |
| Section label (e.g. "ACCOUNT", "AI Assistant") | **10–11 / w600, letterSpacing 1.2**, uppercase |
| Body / description | **14**, `AppColors.textSecondary`, **`height: 1.6`** |
| Onboarding body | **16**, `AppColors.textSecondary`, `height: 1.6` |
| Muted secondary line | 12, `AppColors.textMuted` (e.g. the parse "left out" line uses white54 / 12) |

✅ Three named text colours exist: `AppColors.textPrimary`, `textSecondary`, `textMuted`.

⚠️ **GAP:** their hex values. For mocking, treat them as roughly: primary ≈ near-white,
secondary ≈ white at ~70%, muted ≈ white at ~50%. Confirm from source.

---

## 6. Navigation structure

✅ **Bottom nav, 5 slots:**

```
Home (Dashboard) | Day | [ + Log ] | Routine | History
```

- The **`+ Log`** is the centre item and is the app's primary action — it opens the log entry
  bottom sheet.
- `AppShell` hosts the nav as a persistent `ShellRoute`; it is never popped.
- ⚠️ Nav **icons are white and fine; the labels wash out** against the bright bottom of the
  gradient. Known unfixed issue.

✅ **Full-page routes that show with NO bottom nav** (declared outside the ShellRoute):
`/settings`, `/profile`, `/about`, `/debrief`, `/categories`, `/screen-time`, `/debug-usage`,
`/onboarding`.

---

## 7. Screen-by-screen

### 7.1 Dashboard (`/`)

✅ A `ListView` on the gradient, `SizedBox(height: 12)` between each card, in this exact order:

1. **`CurrentHourCard`**
2. **`DailyIntentionCard`**
3. **`DailyPieChartCard`**
4. **Screen Time card**
5. **Debrief card**

**`CurrentHourCard`** ✅ (as of this session — it was rebuilt):
- A `GlassCard` containing:
  - A top row: the **date** on the left, and a **live `HH:mm` clock** on the right that ticks
    every minute.
  - A small label: **`Right now`** (section-label style — small, uppercase-ish, letterspaced).
  - Below it, **what the routine says for the current hour**: a small **category colour dot**
    (10×10, circle) followed by the slot's name.
  - When the routine has nothing for this hour: **`— nothing planned`**, in
    `AppColors.textMuted`, **italic**, at `titleLarge` size.
- ⚠️ **Note for accuracy:** this card used to show what you *logged* right now. It no longer
  does — the logged readout was deliberately deleted. Do not mock a "logged" line here.

**`DailyPieChartCard`** — a pie chart of today's time by category, `fl_chart`.

**Screen Time card** — surfaces detected screen-time suggestions and carves for confirmation.
⚠️ Its wording is a known polish item ("Screen Time Suggestions / tap Confirm to log detected
screen time" no longer describes everything it holds).

**Debrief card** — entry point into the AI day debrief.

### 7.2 Day View (`/day-view`)

✅ The most visually distinctive screen. A **Google-Calendar-style per-hour row timeline**,
built on the shared `HourTimeline` widget.

Exact geometry (✅ confirmed constants from `lib/core/theme/hour_timeline.dart`):
- `_gutterWidth = 52` — a left gutter holding the hour numbers
- `_laneHeight = 52` — the height of one lane within an hour row
- `_minSegWidth = 48` — minimum rendered width of a segment
- Segment corner radius: **8** (note: *not* the 20 used by cards)

How a row works:
- **24 rows**, one per hour, in a `ListView`. Empty hours still render as empty rows.
- Within a row, an entry is drawn as a **horizontal block**, positioned left-to-right by
  minutes: `left = startMin / 60 * trackWidth`. So a 09:15–09:45 entry sits in the middle of
  the 9 o'clock row.
- **Overlapping entries stack into lanes**, and extra lanes make **that hour's row taller**
  (`rowHeight = laneHeight × laneCount`). Rows are therefore **variable height**.
- Blocks are `GlassCard`s sized to the segment (not to their label).
- Colour comes from the entry's category: `Color(cat.colorValue)`, fallback `0xFF607D8B`
  (a blue-grey) when there's no category.

**The now-line** ✅:
- A **horizontal, full-width line** that slides *down* through the current hour's row
  (`top = minute / 60 * rowHeight`).
- It spans the **block area only, not the hour-number gutter**.
- Drawn last, on top of everything in that row.

**The routine overlay** ✅ — this is the green/amber/red comparison:
- Drawn **behind** the segments, as a per-row **edge** on the left of the block area.
- Structure: a **rounded base block with a uniform faint border**, plus the verdict colour as
  its **own separate left bar** layered on top. (They're separate because Flutter forbids
  combining a border radius with a non-uniform border.)
- Verdict colours: **green** = matched the plan (≥75% coverage + matching category),
  **amber** = partial (≥10%), **red** = missed, **neutral** = not yet past.
- Future hours are neutral; only past hours get a verdict.

**Gestures:** swipe an entry left to delete (red background, no confirm); tap an entry to edit;
tap an empty hour to create a log for that hour and day.

### 7.3 Routine (`/routine`)

✅ Uses the **same `HourTimeline` widget** as Day View, so it looks visually identical in
structure — same gutter, same 52px lanes, same 8px block radius. This was deliberate: one
shared widget so the two screens can't drift apart.

Differences from Day View:
- **Day tabs** at the top to switch between days of the week.
- A **copy-to-days** multi-select action.
- Blocks are routine *slots*, not logged entries. Slot label resolves as:
  **free-text label → category name → `"Unlabelled"`**.
- Slots span multiple hours as one full-height block.
- ⚠️ There is **no visual cue distinguishing an "every day" slot** from a day-specific one.
  An older dimmed-plus-caption treatment was dropped in chat 7 and not replaced.

### 7.4 History (`/history`)

✅ A **weekly stacked bar chart** (`fl_chart`) — one bar per day, Sunday to Saturday,
segmented by category colour. Includes a trend summary row and drill-down into a specific day.

### 7.5 Log entry sheet (the `+ Log` action)

✅ A **bottom sheet** (`showModalBottomSheet` with `useRootNavigator: true`, scroll-controlled)
on `GlassCard` chrome. Top to bottom:

1. **Sleep toggle row** at the very top (`_SleepToggleRow`) — a **`Switch`** with a
   **sun icon (`wb_sunny_rounded`)** when awake and a **moon (`bedtime_rounded`)** when
   sleeping. Sub-label reads **`Awake`** or **`Sleeping since 11:42 PM`**.
   (It is a switch styled with sun/moon icons, not two separately tappable glyphs.)
2. **Sheet header** — 21 / w800.
3. **Unlogged-hours strip** (`_MissedHoursStrip`), labelled **`UNLOGGED HOURS`** — past hours
   of the selected day with no entry, rendered as **tappable chips**.
4. **Time range** — start and end, defaulting to the hour that just ended.
5. **Description** free-text field.
6. **Category picker** — one category per entry, shown as colour chips. An AI-suggested
   category appears as a **highlighted chip you tap to accept**.
7. An **AI "parse from text"** icon button, which opens a second sheet on top where you paste
   a block of text and review the entries the AI extracted before confirming.

### 7.6 Debrief (`/debrief`)

✅ Full-page, no bottom nav. A **streaming AI chat** (SSE, with a blinking cursor while
generating). At its top is the day-rating strip:

- Label: **`How was today?`**
- Two `_VerdictButton`s: **`thumb_up_rounded`** and **`thumb_down_rounded`**.
- Tapping sets the verdict; tapping the same one again **clears it back to unrated**.
- Default state is **unrated** — the app never pre-fills a judgement.

### 7.7 Profile (`/profile`)

✅ A `ListView` with a **`_SectionLabel('ACCOUNT')`** (10–11 / w600 / letterSpacing 1.2)
followed by a stack of **`_LinkTile`** rows.

**`_LinkTile` is the app's standard navigation row** ✅:
- `GlassCard(opacity: 0.08, onTap: ...)`
- **leading icon** → **label** → **trailing chevron**

Current rows: **Categories**, **Settings**, **How ChronoPlan works** (opens onboarding),
**Sync (coming soon)** (disabled — `onTap: null`).

### 7.8 Settings (`/settings`)

✅ A `ListView` of exactly two sections. **No navigation rows** — every row is an inline
control inside a `GlassCard`:

1. **`_SectionLabel('AI Assistant')`** → a card of **`FilterChip`s** for the coach persona:
   *Drill Sergeant*, *Friendly Coach*, *Neutral Analyst*.
2. **`_SectionLabel('Notifications')`** → a card with a **`SegmentedButton`** (hourly vs
   custom interval) and a **`Slider`** for the interval in minutes (range 30–180).

### 7.9 About (`/about`)

✅ Purely static, no interactive rows:
- App icon
- App name at **28 / w800**
- **`Version 1.0.0`**
- A description `GlassCard` (body 14, `textSecondary`, `height: 1.6`)
- A **`CREDITS`** card (mentions Manrope)

### 7.10 Categories (`/categories`)

✅ CRUD list of categories. Each has a name and a colour, picked from a **16-colour picker**.
User-created categories are **archived rather than deleted** (preserves history, hides from
new-entry pickers). **System categories are protected** — notably a **"Screen Time"** category
that cannot be deleted.

⚠️ **GAP:** the 16 palette colours. They are described as a **colourblind-aware palette**.
Suggested defaults on first use are: Work, Exercise, Social, Sleep, Entertainment, Meals,
Personal Care, Learning, Admin, Travel.

### 7.11 Onboarding (`/onboarding`)

✅ Newest screen. Full-page, no bottom nav, on the time-of-day gradient.

- A **`PageView` of 5 full-screen cards**, swiped horizontally.
- Content renders **directly on the gradient — deliberately NOT inside a `GlassCard`**
  (its opaque hit-test would fight the swipe).
- Per card: a **decorative accent icon**, a **heading at 26 / w800 white**, and **body at 16,
  `textSecondary`, `height: 1.6`**.
- A **hand-built dot indicator** (no package): a row of small dots where the **active dot
  widens to 22px** and takes the **hour accent colour**. Animated between pages.
- **Bottom-right action:** a muted **`TextButton` "Skip"** on cards 1–4, which becomes an
  **accent `ElevatedButton` "Get started"** on card 5.

The five headings, in order:
1. Log the hour that just ended
2. You can't log the future
3. Missing hours is normal
4. Tell it when you're asleep
5. You decide how the day went

---

## 8. Component inventory (quick reference for a mockup)

| Component | Description |
|---|---|
| `GlassCard` | White fill 8–12% alpha, backdrop blur sigma 10, radius 20, optional faint border |
| `_LinkTile` | `GlassCard` @ 0.08 + leading icon + label + trailing chevron. The nav row. |
| `_SectionLabel` | 10–11 / w600 / letterSpacing 1.2, uppercase, above a card group |
| Timeline segment | Block in an hour row, radius **8**, category-coloured, min width 48px |
| Hour gutter | 52px wide left column of hour numbers |
| Now-line | Horizontal full-width line inside the current hour's row |
| Routine edge | Rounded faint-bordered base + separate green/amber/red left bar, behind segments |
| Category dot | 10×10 circle, `Color(cat.colorValue)` |
| Verdict buttons | `thumb_up_rounded` / `thumb_down_rounded`, toggleable to unrated |
| Sleep switch | `Switch` + `wb_sunny_rounded` / `bedtime_rounded` + "Sleeping since h:mm a" |
| Unlogged-hours chips | Tappable hour chips under an `UNLOGGED HOURS` label |
| Dot indicator | Row of dots, active widens to 22px in the hour accent colour |
| Persona chips | `FilterChip` row: Drill Sergeant / Friendly Coach / Neutral Analyst |
| Reminder control | `SegmentedButton` + `Slider` (30–180 min) |

---

## 9. Interaction / motion notes

- The **background gradient animates** between palettes (`AnimatedContainer`), it doesn't cut.
- The **clock ticks every minute**; the routine strip only refreshes **on the hour**.
- The **now-line moves every minute** down through the current hour's row.
- **Swipe-to-delete** on entries and routine slots reveals a **red background**, no confirm
  dialog.
- Tasks in the to-do list use a **reveal tray** on swipe (`flutter_slidable`) with a
  **green "Done"** and a **red "Remove"**.
- The **onboarding active dot animates** its width between pages.

---

## 10. What a mockup must NOT show

These are things that were removed or never existed — mocking them would be wrong:

- ❌ A **"LIVE" badge** on entries. Removed in chat 6.
- ❌ A **logged-activity line on the Dashboard's "Right now" card**. Replaced by the routine
  line this session.
- ❌ Any **app-generated score or grade for the day**. The day rating is thumbs-only and
  defaults to unrated. (Routine adherence *is* auto-graded, but only as the green/amber/red
  edges in Day View.)
- ❌ A **missed-hours nudge on the Dashboard or Day View**. Unlogged hours appear **only
  inside the log sheet**.
- ❌ An **API-key entry screen**. Removed when the app moved to the Groq proxy.
- ❌ An **"every day" visual cue** on routine slots. Dropped, not replaced.
- ❌ A **light theme**.

---

## 11. Filling the GAPs — run this to get the real values

Paste into Claude Code. Read-only.

```markdown
# READ-ONLY: extract the design tokens

Do not modify any file. Do not run build or test commands. Read and report.

1. Paste `lib/core/theme/app_colors.dart` IN FULL, verbatim. I need every hex value:
   the four gradient palettes (3 colours each), textPrimary / textSecondary / textMuted,
   every accent, and the category colour palette.
2. Paste `lib/core/theme/app_theme.dart` IN FULL — the whole ThemeData, including any
   colorScheme, scaffold colour, chip/slider/switch theming, and the full text theme.
3. Paste `lib/core/theme/glass_card.dart` IN FULL.
4. Paste `lib/features/dashboard/widgets/current_hour_card.dart` IN FULL.
5. Paste `lib/features/onboarding/onboarding_screen.dart` IN FULL.
6. Paste the bottom navigation bar widget in full — every colour, icon, size, and the
   label styling.
7. Paste `lib/core/theme/hour_timeline.dart`'s constants and its segment-building code.
8. Paste the routine-edge drawing code from `day_view_screen.dart` (the `_routineEdge`
   and verdict-to-colour mapping), including the exact green/amber/red values.
9. Paste the 16-colour category picker list.
10. Report the app's icon and any logo asset paths.

Report each as: file path, then the verbatim code. No summarising — I need exact values.
```

Drop the results into §3, §5 and §7 above and this document becomes fully colour-accurate.
