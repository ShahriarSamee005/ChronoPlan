import 'package:chronoplan/core/onboarding/seen_onboarding_store.dart';
import 'package:chronoplan/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Verbatim card titles (must match onboarding_screen.dart's copy).
const _titles = [
  'Log the hour that just ended',
  "You can't log the future",
  'Missing hours is normal',
  "Tell it when you're asleep",
  'You decide how the day went',
];

const _homeMarker = 'HOME_MARKER';
const _profileMarker = 'PROFILE_MARKER';

GoRouter _buildRouter(String initialLocation) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text(_homeMarker)),
        GoRoute(path: '/profile', builder: (_, __) => const Text(_profileMarker)),
        GoRoute(
            path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      ],
    );

Future<GoRouter> _pump(
  WidgetTester tester, {
  required String initialLocation,
  required SeenOnboardingStore store,
}) async {
  final router = _buildRouter(initialLocation);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [seenOnboardingStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Dispose the tree so TimeGradientBackground cancels its hourly timer.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<void> _swipeNext(WidgetTester tester) async {
  await tester.drag(find.byType(PageView), const Offset(-600, 0));
  await tester.pumpAndSettle();
}

double _dotWidth(WidgetTester tester, int i) =>
    tester.widget<AnimatedContainer>(find.byKey(ValueKey('onboarding_dot_$i')))
        .constraints!
        .maxWidth;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('all 5 cards are reachable by swiping', (tester) async {
    await _pump(tester, initialLocation: '/onboarding', store: SeenOnboardingStore());

    expect(find.text(_titles[0]), findsOneWidget);
    for (var i = 1; i < _titles.length; i++) {
      await _swipeNext(tester);
      expect(find.text(_titles[i]), findsOneWidget,
          reason: 'card ${i + 1} should be reachable by swiping');
    }

    await _teardown(tester);
  });

  testWidgets('Skip marks the flag and lands on /', (tester) async {
    final store = SeenOnboardingStore();
    await _pump(tester, initialLocation: '/onboarding', store: store);

    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text(_homeMarker), findsOneWidget);
    expect(await store.value(), isTrue, reason: 'skip must mark onboarding seen');

    await _teardown(tester);
  });

  testWidgets('finishing the last card marks the flag and lands on /',
      (tester) async {
    final store = SeenOnboardingStore();
    await _pump(tester, initialLocation: '/onboarding', store: store);

    for (var i = 1; i < _titles.length; i++) {
      await _swipeNext(tester);
    }
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text(_homeMarker), findsOneWidget);
    expect(await store.value(), isTrue);

    await _teardown(tester);
  });

  testWidgets('opened from Profile, finishing returns to Profile — not /',
      (tester) async {
    final store = SeenOnboardingStore();
    final router =
        await _pump(tester, initialLocation: '/profile', store: store);

    // Replay: pushed on top of Profile (like the _LinkTile does).
    router.push('/onboarding');
    await tester.pumpAndSettle();
    expect(find.text(_titles[0]), findsOneWidget);

    for (var i = 1; i < _titles.length; i++) {
      await _swipeNext(tester);
    }
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text(_profileMarker), findsOneWidget,
        reason: 'replay must return to origin');
    expect(find.text(_homeMarker), findsNothing,
        reason: 'replay must NOT reset to home');

    await _teardown(tester);
  });

  testWidgets('the dot indicator reflects the current page', (tester) async {
    await _pump(tester, initialLocation: '/onboarding', store: SeenOnboardingStore());

    // Page 0 active.
    expect(_dotWidth(tester, 0), greaterThan(_dotWidth(tester, 1)));

    await _swipeNext(tester);

    // Page 1 now active; page 0 shrank.
    expect(_dotWidth(tester, 1), greaterThan(_dotWidth(tester, 0)));

    await _teardown(tester);
  });
}
