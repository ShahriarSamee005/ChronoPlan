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
}
