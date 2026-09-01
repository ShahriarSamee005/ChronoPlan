# Gradient Diagnostic Report

## 1. The hour-to-palette mapping

### `gradientForHour` (app_colors.dart:29-34)

```dart
static List<Color> gradientForHour(int hour) {
  if (hour >= 5 && hour < 11) return _morning;
  if (hour >= 11 && hour < 17) return _midday;
  if (hour >= 17 && hour < 21) return _evening;
  return _night;
}
```

### `accentForHour` (app_colors.dart:37-42)

```dart
static Color accentForHour(int hour) {
  if (hour >= 5 && hour < 11) return const Color(0xFFFF8A65); // warm orange
  if (hour >= 11 && hour < 17) return const Color(0xFF29B6F6); // sky blue
  if (hour >= 17 && hour < 21) return const Color(0xFFCE93D8); // lilac
  return const Color(0xFF7986CB); // soft indigo
}
```

### Hour-by-hour mapping

| Hours | Palette  |
|-------|----------|
| 0-4   | _night   |
| 5-10  | _morning |
| 11-16 | _midday  |
| 17-20 | _evening |
| 21-23 | _night   |

**No hour falls through to an unintended default.** The branches are mutually exclusive and exhaustive. Boundaries use `>=` and `<` consistently — no off-by-one issues, no overlap, no gap.

### The four palettes (app_colors.dart:8-27)

```dart
static const _morning = [
  Color(0xFF3D1C0A), // deep burnt orange    — RGB(61, 28, 10)
  Color(0xFF7B3500), // amber-brown          — RGB(123, 53, 0)
  Color(0xFF4A1800), // dark sienna          — RGB(74, 24, 0)
];
static const _midday = [
  Color(0xFF071428), // deep navy            — RGB(7, 20, 40)
  Color(0xFF0D2137), // ocean blue           — RGB(13, 33, 55)
  Color(0xFF0A2744), // slate blue           — RGB(10, 39, 68)
];
static const _evening = [
  Color(0xFF1A0630), // deep violet          — RGB(26, 6, 48)
  Color(0xFF2D0B50), // dark purple          — RGB(45, 11, 80)
  Color(0xFF3D1A10), // ember                — RGB(61, 26, 16)
];
static const _night = [
  Color(0xFF04060F), // near black           — RGB(4, 6, 15)
  Color(0xFF080D22), // deep indigo          — RGB(8, 13, 34)
  Color(0xFF060D1E), // midnight             — RGB(6, 13, 30)
];
```

**The four palettes ARE different hues** (warm brown, blue, purple, near-black) **but ALL are extremely dark.** The brightest channel value across all 12 colors is 123 (out of 255). On a typical phone screen at normal/low brightness these will appear very similar — all read as "dark with a faint tint."

### `paletteAt` (app_colors.dart:59)

```dart
static Color paletteAt(int index) => palette[index % palette.length];
```

This is the **category** palette (line 46-57), unrelated to the time-of-day gradient. It is NOT used by the gradient background.

---

## 2. How the widget reads "now" on load

### Full widget source (time_gradient_background.dart:1-65)

```dart
class TimeGradientBackground extends StatefulWidget {
  final Widget child;
  const TimeGradientBackground({super.key, required this.child});

  @override
  State<TimeGradientBackground> createState() =>
      _TimeGradientBackgroundState();
}

class _TimeGradientBackgroundState extends State<TimeGradientBackground> {
  late List<Color> _colors;
  Timer? _hourTimer;

  @override
  void initState() {
    super.initState();
    _colors = AppColors.gradientForHour(DateTime.now().hour);   // line 26
    _scheduleNextHour();
  }

  void _scheduleNextHour() {
    final now = DateTime.now();
    final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
    final delay = nextHour.difference(now);
    _hourTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _colors = AppColors.gradientForHour(DateTime.now().hour));
      _scheduleNextHour();
    });
  }

  @override
  void dispose() {
    _hourTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(seconds: 3),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _colors,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: widget.child,
    );
  }
}
```

### How it gets the current hour

- **`initState` (line 26):** calls `DateTime.now().hour` directly — this is the real system clock, not a fixed value.
- **`_colors` initial value:** set from the real current hour on first frame. No hardcoded default.
- **`_hourTimer` / `_scheduleNextHour`:** schedules a timer to fire at the top of the next hour and update `_colors` via `setState`. Correctly re-arms for subsequent hours.
- **No constructor parameter for hour.** The widget always reads the clock itself.
- **No provider dependency.** No stale value from a parent.

The widget's clock-reading logic is correct. Each fresh mount (app open, navigation) will read the real hour.

---

## 3. Who renders it, and with what

`TimeGradientBackground` is used **app-wide** across 10 screens, always as `body: TimeGradientBackground(child: SafeArea(...))` with only `child` passed — **no call site passes a fixed hour**:

| File | Line |
|------|------|
| lib/features/dashboard/dashboard_screen.dart | 133 |
| lib/features/day_view/day_view_screen.dart | 123 |
| lib/features/routine/routine_screen.dart | 115 |
| lib/features/screen_time/screen_time_screen.dart | 44 |
| lib/features/settings/settings_screen.dart | 37 |
| lib/features/profile/profile_screen.dart | 93 |
| lib/features/history/history_screen.dart | 94 |
| lib/features/about/about_screen.dart | 29 |
| lib/features/debrief/debrief_screen.dart | 270 |
| lib/features/categories/categories_screen.dart | 52 |

---

## 4. Verdict

**Most likely cause: (b) — the four palettes are visually too similar.**

The branch logic in `gradientForHour` is correct (all 24 hours covered, no overlap, no fallthrough). The widget reads `DateTime.now().hour` fresh in `initState` on every mount. No call site passes a fixed hour. The palettes use genuinely different hues (warm brown, blue, purple, near-black), **but every single color across all four palettes is extremely dark** — the brightest RGB channel is 123/255 (48%). On a phone screen at typical brightness, the four gradients will appear as "dark with a barely perceptible color tint," making them look essentially the same.

**Responsible lines:** `app_colors.dart:8-27` — the `_morning`, `_midday`, `_evening`, and `_night` color definitions.
