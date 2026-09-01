# Gradient Render-Layer Diagnostic

## 1. Dashboard render tree

**File:** `lib/features/dashboard/dashboard_screen.dart`

### Build method root → content (lines 105-151):

```dart
return Scaffold(                                   // line 105
  backgroundColor: Colors.transparent,             // line 106 — TRANSPARENT
  extendBodyBehindAppBar: true,                    // line 107
  appBar: AppBar(                                  // line 108
    backgroundColor: Colors.transparent,           // line 109 — TRANSPARENT
    elevation: 0,                                  // line 110
    scrolledUnderElevation: 0,                     // line 111
    ...
  ),
  body: TimeGradientBackground(                    // line 133
    child: SafeArea(                               // line 134
      child: ListView(                             // line 135
        ...
      ),
    ),
  ),
);
```

- **Root:** `Scaffold` with `backgroundColor: Colors.transparent` (line 106). Not opaque.
- **AppBar:** `backgroundColor: Colors.transparent`, `elevation: 0`, `scrolledUnderElevation: 0` (lines 109-111). Not opaque. No shadow.
- **`TimeGradientBackground` position:** It IS the `body` of the Scaffold (line 133). It is NOT inside a Stack. There is no layer painted above the gradient other than the transparent AppBar and the content (text, cards with semi-transparent glass surfaces).
- **No opaque widget covers the gradient.** The content children (cards) use `Colors.white.withValues(alpha: 0.07)` backgrounds (e.g. line 197) — 7% white, not opaque.

---

## 2. The shell above it

**File:** `lib/features/shell/app_shell.dart`

### Relevant lines (65-68):

```dart
return Scaffold(                                   // line 65
  backgroundColor: Colors.transparent,             // line 66 — TRANSPARENT
  extendBody: true,                                // line 67
  body: widget.child,                              // line 68
  bottomNavigationBar: _GlassNavBar(...),          // line 69
);
```

- The shell's Scaffold sets `backgroundColor: Colors.transparent` (line 66).
- The Dashboard (and its gradient) is rendered as `widget.child` inside the shell's body (line 68).
- The shell's Scaffold does NOT paint an opaque background over the gradient.
- `extendBody: true` (line 67) lets the body extend behind the bottom nav bar, which is also glass/translucent (`Color(0x14FFFFFF)` — 8% white, line 111).

**Nesting order (outside → inside):**
1. AppShell Scaffold (transparent) → body: Dashboard
2. Dashboard Scaffold (transparent) → body: TimeGradientBackground
3. TimeGradientBackground (AnimatedContainer with gradient)

No opaque layer anywhere in the chain.

---

## 3. The theme default

**File:** `lib/core/theme/app_theme.dart`

### scaffoldBackgroundColor (line 14):

```dart
scaffoldBackgroundColor: Colors.transparent,       // line 14
```

The theme default for scaffold background is `Colors.transparent`. Any screen that doesn't explicitly override this will inherit transparent — meaning the gradient shows through.

### ColorScheme surface (line 18):

```dart
surface: Color(0xFF080D22),                        // line 18 — deep indigo/navy
```

This `0xFF080D22` (RGB 8, 13, 34) is a dark navy. It matches the `_night` palette's second color (`0xFF080D22`, app_colors.dart line 25). This is what the user sees as the "dark navy" — but it is NOT being painted as a scaffold background (that's transparent). It could appear if any Material widget falls back to `colorScheme.surface`, but the Scaffolds all set explicit transparent backgrounds.

**Note:** The value `0xFF080D22` is the underlying FlutterView/engine background on dark theme, which would be visible through all the transparent layers if the gradient somehow failed to paint. But the gradient does paint (see section 4).

---

## 4. The gradient widget itself

**File:** `lib/features/dashboard/widgets/time_gradient_background.dart`

### Confirmed:

- **`_colors` is initialized from the real clock:** `_colors = AppColors.gradientForHour(DateTime.now().hour)` (line 26). No hardcoded default.
- **The `AnimatedContainer` fills the screen:** It is the `body` of the Scaffold, which in Flutter fills all available space. No `SizedBox.shrink`, no `Opacity(opacity: 0)`, no early return, no conditional that could skip it.
- **`LinearGradient` uses `_colors`:** lines 55-59. Three colors, three stops `[0.0, 0.5, 1.0]`, `topLeft → bottomRight`.
- **No visibility guard:** The widget always paints the gradient. There is no condition, feature flag, or setting that hides it.

The gradient widget is structurally correct and always renders.

---

## 5. Palette values (for the record)

From `lib/core/theme/app_colors.dart` lines 8-27:

| Palette   | Color 1 (ARGB)   | Color 2 (ARGB)   | Color 3 (ARGB)   |
|-----------|------------------|------------------|-------------------|
| _morning  | 0xFF3D1C0A (61,28,10) | 0xFF7B3500 (123,53,0) | 0xFF4A1800 (74,24,0) |
| _midday   | 0xFF071428 (7,20,40) | 0xFF0D2137 (13,33,55) | 0xFF0A2744 (10,39,68) |
| _evening  | 0xFF1A0630 (26,6,48) | 0xFF2D0B50 (45,11,80) | 0xFF3D1A10 (61,26,16) |
| _night    | 0xFF04060F (4,6,15) | 0xFF080D22 (8,13,34) | 0xFF060D1E (6,13,30) |

All four palettes are different hues but extremely dark. The brightest single channel across all 12 colors is R=123 in `_morning[1]`. Most values are below 50/255.

---

## 6. Verdict

**The gradient IS VISIBLE on the Dashboard — it is NOT covered by an opaque layer.**

Both Scaffolds (AppShell line 66, Dashboard line 106) and the theme (line 14) all set `backgroundColor: Colors.transparent`. The AppBar is transparent with zero elevation (lines 109-111). No Stack, no opaque Container, no ColoredBox sits above the gradient. The `TimeGradientBackground` AnimatedContainer fills the body and always paints.

**The issue is purely the palette values.** All four palettes (`app_colors.dart:8-27`) are extremely dark — designed as "dark bases" for glass morphism. On a phone screen at normal brightness:

1. **If the user tests only during work hours (11:00-16:59),** they always see the `_midday` palette (dark navy: 0xFF071428 / 0xFF0D2137 / 0xFF0A2744). The gradient literally never changes because the hour never leaves the midday range during their testing.

2. **Even across different time periods,** the four palettes are so dark that the hue differences (warm brown vs. navy vs. purple vs. near-black) are barely perceptible on most screens.

**Root cause:** `app_colors.dart:8-27` — the `_morning`, `_midday`, `_evening`, `_night` color values need to be brighter/more saturated to produce visually distinguishable gradients.
