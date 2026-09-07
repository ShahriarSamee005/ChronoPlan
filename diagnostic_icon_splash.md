# ChronoPlan — Diagnostic: app icon + splash + font loading

READ-ONLY fact-gathering. Nothing in the app was changed. This report records
the current wired state only; no fixes are proposed or applied.

---

## 1. pubspec.yaml

### `flutter_launcher_icons:` block (verbatim)

```yaml
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/branding/Chronoplan logo 5 icon.png"
  adaptive_icon_background: "#BFD5F5"
  adaptive_icon_foreground: "assets/branding/Chronoplan logo 5 icon.png"
  min_sdk_android: 21
```

### `flutter:` section (verbatim)

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/branding/
```

- There is **no `fonts:` section** in the `flutter:` block — MISSING.
- The `assets:` list contains exactly one entry: the directory `assets/branding/`.

### Relevant dependency versions

| Package | Where | Constraint |
|---|---|---|
| `flutter_launcher_icons` | dev_dependencies | `^0.14.4` |
| `flutter_native_splash` | dev_dependencies | `^2.4.8` |
| `google_fonts` | dependencies | `^6.2.1` |

### `flutter_native_splash:` block inside pubspec.yaml?

**MISSING** — there is no `flutter_native_splash:` block in pubspec.yaml. It
lives only in the separate `flutter_native_splash.yaml` file. **No conflict.**

---

## 2. flutter_native_splash.yaml (verbatim)

```yaml
flutter_native_splash:
  # All branding now happens in Flutter (see SplashGate). The native splash is a
  # plain solid colour that matches SplashGate's base, so the OS-splash → Flutter
  # hand-off shows no jump. `color` and `background_image` are mutually
  # exclusive; only `color` is set here.
  color: "#BFD5F5"

  android: true
  ios: false
  web: false

  # Android 12+ system splash: solid colour with the masked icon. The icon
  # background is set equal to the page colour so the icon shows no visible box.
  android_12:
    color: "#BFD5F5"
    icon_background_color: "#BFD5F5"
    image: "assets/branding/icon_foreground.png"
```

- An **`android_12:` block exists.** Keys it sets:
  - `color: "#BFD5F5"`
  - `icon_background_color: "#BFD5F5"`
  - `image: "assets/branding/icon_foreground.png"`
- The top-level block sets **only `color`** — no `image:` and no
  `background_image:` for the pre-Android-12 splash.

---

## 3. assets/branding/

Recursive file listing with dimensions, size, and whether the file is shipped in
the APK.

The `assets:` list contains only `assets/branding/` (the directory). In Flutter,
a directory entry bundles files **directly inside** that directory but **not**
files in sub-directories. So everything in `assets/branding/source/` is **NOT
shipped**.

### Directly in `assets/branding/` — SHIPPED

| File | Dimensions | Size | In APK |
|---|---|---|---|
| `Chronoplan logo 5 icon.png` | 1024 × 1024 | 1183.2 KB | ✅ yes |
| `Chronoplan logo 5.png` | 1254 × 1254 | 1590.7 KB | ✅ yes |
| `icon_background.png` | 1024 × 1024 | 714.0 KB | ✅ yes |
| `icon_foreground.png` | 1024 × 1024 | 352.7 KB | ✅ yes |
| `logo.png` | 1254 × 1254 | 890.6 KB | ✅ yes |
| `splash.png` | 1087 × 1446 | 446.7 KB | ✅ yes |
| `splash_android12.png` | 1152 × 1152 | 189.6 KB | ✅ yes |
| `wordmark.png` | 998 × 197 | 12.1 KB | ✅ yes |

### In `assets/branding/source/` — NOT SHIPPED

| File | Dimensions | Size | In APK |
|---|---|---|---|
| `source/Chronoplan logo 5.png` | 1254 × 1254 | 1590.7 KB | ❌ no |
| `source/logo png .png` | 1254 × 1254 | 890.6 KB | ❌ no |
| `source/Project 3 (6).png` | 1080 × 2237 | 21.7 KB | ❌ no |
| `source/splash_background.png` | 1440 × 3120 | 270.9 KB | ❌ no |
| `source/splash_logo.png` | 760 × 840 | 286.5 KB | ❌ no |

Note: `splash_android12.png` (1152 × 1152) ships but is **not referenced** by the
current `flutter_native_splash.yaml` (which points `android_12.image` at
`icon_foreground.png`).

---

## 4. The Flutter splash overlay

### `lib/features/splash/splash_gate.dart` (verbatim)

```dart
import 'dart:async';

import 'package:flutter/material.dart';

/// A branded splash overlaid on top of [child] for the first moments after
/// launch. It sits ABOVE whatever the router built — it never decides what that
/// is, so the onboarding-vs-dashboard choice made in `main()` before `runApp`
/// is untouched. Once dismissed it removes itself from the tree entirely.
///
/// Frame one paints a solid `#BFD5F5` base — the same colour as the native
/// splash — so there is no visible jump from the OS splash to this one. The
/// gradient and the logo/wordmark then fade in on top of that base; after
/// [minimumVisible] the whole overlay fades out over [fadeOut] and is gone.
class SplashGate extends StatefulWidget {
  final Widget child;

  const SplashGate({super.key, required this.child});

  /// How long the splash stays fully present, measured from the first frame,
  /// before it begins fading out. Tests reference this instead of a literal.
  static const Duration minimumVisible = Duration(milliseconds: 1200);

  /// How long the whole overlay takes to fade out before it leaves the tree.
  static const Duration fadeOut = Duration(milliseconds: 350);

  /// How long the gradient + content take to fade in over the solid base.
  static const Duration _fadeIn = Duration(milliseconds: 400);

  /// Base / native-splash colour. Kept in sync with `flutter_native_splash.yaml`
  /// and the launcher icon background so the hand-off shows no jump.
  static const Color _baseColor = Color(0xFFBFD5F5);

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with TickerProviderStateMixin {
  late final AnimationController _fadeInController = AnimationController(
    vsync: this,
    duration: SplashGate._fadeIn,
  );

  late final AnimationController _fadeOutController = AnimationController(
    vsync: this,
    duration: SplashGate.fadeOut,
  );

  /// Whole-overlay opacity: 1 while shown, animating to 0 as it dismisses.
  late final Animation<double> _overlayOpacity = Tween<double>(
    begin: 1.0,
    end: 0.0,
  ).animate(CurvedAnimation(parent: _fadeOutController, curve: Curves.easeOut));

  /// Gradient + content fade-in over the solid base.
  late final Animation<double> _contentOpacity = CurvedAnimation(
    parent: _fadeInController,
    curve: Curves.easeOut,
  );

  Timer? _holdTimer;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _fadeInController.forward();

    // Hold from the first frame, then dismiss.
    _holdTimer = Timer(SplashGate.minimumVisible, () {
      if (!mounted) return;
      _fadeOutController.forward();
    });

    _fadeOutController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _removed = true);
      }
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _fadeInController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_removed)
          // Dismisses on a timer, so it must never swallow taps meant for the
          // child — IgnorePointer, not a gesture detector.
          IgnorePointer(
            key: const ValueKey('splash_overlay'),
            child: FadeTransition(
              opacity: _overlayOpacity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Solid base — matches the native splash, painted from frame one.
                  const ColoredBox(color: SplashGate._baseColor),
                  // Gradient + branded content fade in together over the base.
                  FadeTransition(
                    opacity: _contentOpacity,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: [0.0, 1.0],
                          colors: [Color(0xFFD3E2F8), Color(0xFF4883DE)],
                        ),
                      ),
                      child: Center(
                        // Single merged logo+wordmark. No colour filter — the
                        // wordmark is white by design.
                        child: Image.asset(
                          'assets/branding/splash.png',
                          key: const ValueKey('splash_content'),
                          width: 210,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
```

The overlay renders **`assets/branding/splash.png`** at `width: 210`.

### `lib/app.dart` (verbatim)

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/splash_gate.dart';

class ChronoPlanApp extends StatelessWidget {
  /// Built in `main()` with the first-frame initial location already resolved
  /// from the seen-onboarding flag.
  final GoRouter router;

  const ChronoPlanApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    return MaterialApp.router(
      title: 'ChronoPlan',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // The splash overlays whatever the router built; it never decides the
      // route. The onboarding-vs-dashboard choice stays in main() before runApp.
      builder: (context, child) =>
          SplashGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
```

### Every `SplashGate` hit in the repo

| File | Line | Context |
|---|---|---|
| `lib/app.dart` | 6 | `import '.../splash_gate.dart';` |
| `lib/app.dart` | 29 | `SplashGate(child: child ?? const SizedBox.shrink())` — wired into `MaterialApp.router` builder |
| `lib/features/splash/splash_gate.dart` | 14 | class declaration |
| `lib/features/splash/splash_gate.dart` | 17 | constructor |
| `lib/features/splash/splash_gate.dart` | 34 | `createState()` |
| `lib/features/splash/splash_gate.dart` | 37 | `_SplashGateState` |
| `lib/features/splash/splash_gate.dart` | 41, 46, 70, 106 | internal uses of static consts |
| `test/splash_gate_test.dart` | 9, 23, 49, 50, 80, 104 | tests |
| `ChronoPlan 9.md` | 140, 141, 151, 155, 157, 196 | design doc references (non-code) |

### `test/splash_gate_test.dart` (verbatim)

```dart
import 'package:chronoplan/features/dashboard/dashboard_screen.dart';
import 'package:chronoplan/features/splash/splash_gate.dart';
import 'package:chronoplan/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wrap a marker child in a SplashGate under a minimal MaterialApp.
Widget _wrap(Widget child) => MaterialApp(home: SplashGate(child: child));

/// Assert against a realistic phone viewport rather than the default 800×600 —
/// a splash covers a real device screen, and the surface size shouldn't just
/// happen to fit. This sizes the viewport only — no pixels or widget code.
void _setPhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

const _overlay = ValueKey('splash_overlay');
const _content = ValueKey('splash_content');

/// Unmount everything so SplashGate.dispose cancels its hold timer and any
/// hourly timers (TimeGradientBackground) stop before the test ends.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('renders its branded content on the first pump', (tester) async {
    _setPhoneSurface(tester);
    await tester.pumpWidget(_wrap(const Text('CHILD')));

    expect(find.byKey(_overlay), findsOneWidget);
    expect(find.byKey(_content), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('after minimumVisible + fadeOut the splash is gone and the '
      'child is visible', (tester) async {
    _setPhoneSurface(tester);
    await tester.pumpWidget(_wrap(const Text('CHILD')));
    expect(find.byKey(_overlay), findsOneWidget);

    // Hold, then the timer starts the fade-out; settle it to completion and let
    // the removal rebuild land.
    await tester.pump(SplashGate.minimumVisible);
    await tester.pump(SplashGate.fadeOut);
    await tester.pumpAndSettle();

    expect(find.byKey(_overlay), findsNothing);
    expect(find.text('CHILD'), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('the child is in the tree from the first frame — splash overlays, '
      'not replaces', (tester) async {
    _setPhoneSurface(tester);
    await tester.pumpWidget(_wrap(const Text('CHILD')));

    // Both present on frame one: the child underneath and the overlay on top.
    expect(find.text('CHILD'), findsOneWidget);
    expect(find.byKey(_overlay), findsOneWidget);

    await _teardown(tester);
  });

  testWidgets('over a router at /onboarding, onboarding shows underneath — '
      'not the Dashboard (no-flash rule holds)', (tester) async {
    _setPhoneSurface(tester);
    final router = createRouter(initialLocation: '/onboarding');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              SplashGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
    await tester.pump();

    // The router's initial route built onboarding; the splash overlays it.
    expect(find.byKey(_overlay), findsOneWidget);
    expect(find.text('Log the hour that just ended'), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);

    await _teardown(tester);
    router.dispose();
  });

  testWidgets('the branded content actually fades in to visible — not just '
      'present in the tree', (tester) async {
    _setPhoneSurface(tester);
    await tester.pumpWidget(_wrap(const Text('CHILD')));

    // Pump past the fade-in. minimumVisible (a real constant) is longer than
    // the content fade-in, so by here the content controller has reached 1.0.
    // The fade-out that starts at this instant drives the OUTER overlay
    // opacity, not the content layer asserted below.
    await tester.pump(SplashGate.minimumVisible);

    // The FadeTransition closest to the branded image is the one driving the
    // content's opacity. Assert it is genuinely visible, not stuck near zero
    // (the exact failure mode a tree-presence check would have missed).
    final contentFade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(_content),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(contentFade.opacity.value, greaterThan(0.9));

    await _teardown(tester);
  });
}
```

---

## 5. Generated Android icon + splash files

### `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` (verbatim)

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground>
      <inset
          android:drawable="@drawable/ic_launcher_foreground"
          android:inset="16%" />
  </foreground>
</adaptive-icon>
```

### `ic_launcher_background` entry — `android/app/src/main/res/values/colors.xml` (verbatim)

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#BFD5F5</color>
</resources>
```

There is no separate `values/ic_launcher_background.xml`; the color is defined in
`values/colors.xml`.

### `android/app/src/main/res/drawable/launch_background.xml` (verbatim)

```xml
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <bitmap android:gravity="fill" android:src="@drawable/background"/>
    </item>
</layer-list>
```

> NOTE (fact, not a fix): this generated file fills the pre-Android-12 window
> background with a **bitmap** `@drawable/background` (`drawable/background.png`
> and `drawable-v21/background.png` both exist on disk). The **current**
> `flutter_native_splash.yaml` top-level block sets **only `color`** with no
> image — meaning these generated files were produced by an earlier
> generator run whose config differed from the yaml now on disk. The generator
> has not been re-run since the yaml was changed.

### `android/app/src/main/res/values/styles.xml` (verbatim)

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is off -->
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <!-- Show a splash screen on the activity. Automatically removed when
             the Flutter engine draws its first frame -->
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.

         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

### `android/app/src/main/res/values-v31/styles.xml` (verbatim)

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the OS's Dark Mode setting is off -->
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowFullscreen">false</item>
        <item name="android:windowDrawsSystemBarBackgrounds">false</item>
        <item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>
        <item name="android:windowSplashScreenBackground">#BFD5F5</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/android12splash</item>
        <item name="android:windowSplashScreenIconBackgroundColor">#BFD5F5</item>
    </style>
    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your
         Flutter UI initializes, as well as behind your Flutter UI while its
         running.
         
         This Theme is only used starting with V2 of Flutter's Android embedding. -->
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

### `android/app/src/main/AndroidManifest.xml` — `<application>` / `<activity>` opening tags

```xml
<application
    android:label="chronoplan"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">

    <activity
        android:name=".MainActivity"
        android:exported="true"
        android:launchMode="singleTop"
        android:taskAffinity=""
        android:theme="@style/LaunchTheme"
        android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
        android:hardwareAccelerated="true"
        android:windowSoftInputMode="adjustResize">
```

- `android:label` = **`chronoplan`**
- `android:icon` = **`@mipmap/ic_launcher`**
- activity `android:theme` = **`@style/LaunchTheme`**

### Plain statement — background layer of `ic_launcher.xml`

`ic_launcher.xml` references a **`@color`** for its background layer
(`@color/ic_launcher_background`, which resolves to `#BFD5F5`). It does **not**
use a drawable for the background. (The foreground layer uses a drawable,
`@drawable/ic_launcher_foreground`, inset 16%.)

---

## 6. Font loading

### `GoogleFonts` / `google_fonts` call sites in `lib/`

| File | Line | Call |
|---|---|---|
| `lib/core/theme/app_theme.dart` | 2 | `import 'package:google_fonts/google_fonts.dart';` |
| `lib/core/theme/app_theme.dart` | 11 | `GoogleFonts.manropeTextTheme(base.textTheme)` |
| `lib/core/theme/app_theme.dart` | 22 | `GoogleFonts.manrope(...)` — displayLarge |
| `lib/core/theme/app_theme.dart` | 27 | `GoogleFonts.manrope(...)` — titleLarge |
| `lib/core/theme/app_theme.dart` | 32 | `GoogleFonts.manrope(...)` — titleMedium |
| `lib/core/theme/app_theme.dart` | 37 | `GoogleFonts.manrope(...)` — bodyLarge |
| `lib/core/theme/app_theme.dart` | 41 | `GoogleFonts.manrope(...)` — bodyMedium |
| `lib/core/theme/app_theme.dart` | 45 | `GoogleFonts.manrope(...)` — labelSmall |
| `lib/core/theme/app_theme.dart` | 72 | `GoogleFonts.manrope(...)` — hintStyle |
| `lib/core/theme/app_theme.dart` | 76 | `GoogleFonts.manrope(...)` — labelStyle |
| `lib/core/theme/app_theme.dart` | 96 | `GoogleFonts.manrope(...)` — button textStyle |
| `lib/core/theme/app_theme.dart` | 109 | `GoogleFonts.manrope(...)` — chip labelStyle |

All font usage is confined to `lib/core/theme/app_theme.dart`.

### Font-related part of `lib/core/theme/app_theme.dart`

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark();
    final manrope = GoogleFonts.manropeTextTheme(base.textTheme);

    return base.copyWith(
      // ...
      textTheme: manrope.copyWith(
        displayLarge: GoogleFonts.manrope(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 32,
        ),
        titleLarge: GoogleFonts.manrope(...),
        titleMedium: GoogleFonts.manrope(...),
        bodyLarge: GoogleFonts.manrope(...),
        bodyMedium: GoogleFonts.manrope(...),
        labelSmall: GoogleFonts.manrope(...),
      ),
      // ...remaining component themes also call GoogleFonts.manrope(...)
    );
  }
}
```

The base text theme comes from `GoogleFonts.manropeTextTheme(base.textTheme)`,
and individual styles are set with `GoogleFonts.manrope(...)`.

### `assets/fonts/` folder?

**MISSING** — no `assets/fonts/` directory exists.

### `fonts:` section in pubspec.yaml?

**MISSING** — no `fonts:` section in pubspec.yaml.

Consequence (fact): because no Manrope files are bundled and no `fonts:` entry
exists, `google_fonts` fetches Manrope over the network at runtime (and caches
it), rather than loading a bundled asset.

---

## 7. Android SDK levels

From `android/app/build.gradle.kts`:

| Key | Value |
|---|---|
| `compileSdk` | `36` (literal) |
| `minSdk` | `flutter.minSdkVersion` (delegated to the Flutter Gradle plugin default) |
| `targetSdk` | `flutter.targetSdkVersion` (delegated to the Flutter Gradle plugin default) |
| `applicationId` | `com.example.chronoplan` |
| `namespace` | `com.example.chronoplan` |

Note: `minSdk` and `targetSdk` are **not** pinned to literals in the gradle file
— they resolve to the Flutter toolchain's defaults at build time. The
`min_sdk_android: 21` in the `flutter_launcher_icons` block only governs icon
generation, not the app's build `minSdk`.

---

## 8. Baseline

### `flutter analyze`

```
Analyzing chronoplan...
No issues found! (ran in 47.6s)
```

**Clean — no issues.**

### `flutter test`

**237 passed · 0 failed · 7 skipped.**

The 7 skipped tests are **time-of-day self-skips** — they call
`markTestSkipped(...)` at runtime because they need one or two elapsed hours in
the current day, and this run happened in a window where that condition wasn't
met. They are not disabled tests.

| Test file | Skipped test | Skip reason (from `markTestSkipped`) |
|---|---|---|
| `test/pending_reconciliation_count_test.dart` | "counts empty-hour suggestions and carve hours together" | `needs two elapsed hours today` |
| `test/pending_reconciliation_count_test.dart` | "several carves on one logged hour count as a single item" | `needs one elapsed hour today` |
| `test/pending_reconciliation_count_test.dart` | "the card stays visible with carves but zero suggestions" | `needs one elapsed hour today` |
| `test/pending_reconciliation_count_test.dart` | "two apps in one logged hour render as two separate rows" | `needs one elapsed hour today` |
| `test/usage_suggestion_confirm_test.dart` | "the suggestion carries the hour's detected total" | `no elapsed hour exists before 01:00` |
| `test/usage_suggestion_confirm_test.dart` | "a confirmed screen-time block is never offered as a carve target" | `no elapsed hour exists before 01:00` |
| `test/usage_suggestion_confirm_test.dart` | "a user-origin entry in the same shape still yields a carve proposal" | `no elapsed hour exists before 01:00` |

(The exact set of 7 that skip can vary with the wall-clock hour the suite runs
at; the skip guards live at `pending_reconciliation_count_test.dart:79,111,152,205`
and `usage_suggestion_confirm_test.dart:63,102,143`.)

---

## WHAT IS ACTUALLY WIRED RIGHT NOW

1. **Which image files does the icon generator currently point at?**
   The `flutter_launcher_icons` config points at
   `assets/branding/Chronoplan logo 5 icon.png` for **both** `image_path` and
   `adaptive_icon_foreground`, with `adaptive_icon_background` set to the solid
   colour `#BFD5F5`. (The already-generated Android files reflect this: adaptive
   background = `@color/ic_launcher_background` = `#BFD5F5`, foreground =
   `@drawable/ic_launcher_foreground` inset 16%.)

2. **Which image files does the splash generator currently point at?**
   `flutter_native_splash.yaml` points the **pre-Android-12** splash at **no
   image at all** — only `color: "#BFD5F5"`. The **Android 12+** splash points at
   `assets/branding/icon_foreground.png` on a `#BFD5F5` background.
   ⚠️ The generated Android splash files on disk do **not** match this: the
   generated `launch_background.xml` still fills the window with a bitmap
   `@drawable/background`, and v31 uses `@drawable/android12splash` — artifacts
   of an earlier generator run. Also, `assets/branding/splash_android12.png`
   ships but is not referenced by the current yaml.

3. **Is the Flutter SplashGate overlay currently active on app start?**
   **Yes.** `lib/app.dart:29` wraps the router's child in `SplashGate` via the
   `MaterialApp.router` `builder`. It paints a `#BFD5F5` base, fades in a
   gradient plus `assets/branding/splash.png`, holds 1200 ms, then fades out over
   350 ms and removes itself.

4. **Is Manrope loaded from the network, from bundled assets, or both?**
   **From the network only.** All text uses `GoogleFonts.manrope*` from the
   `google_fonts` package, there is no `assets/fonts/` folder, and there is no
   `fonts:` section in pubspec.yaml — so Manrope is fetched at runtime and cached
   by `google_fonts`, not bundled in the APK.

---

*End of diagnostic. No fixes proposed or applied.*
