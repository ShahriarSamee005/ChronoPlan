import 'package:chronoplan/core/onboarding/seen_onboarding_store.dart';
import 'package:chronoplan/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('initialRouteForOnboarding (pure gate)', () {
    test('unseen → /onboarding', () {
      expect(initialRouteForOnboarding(seen: false), '/onboarding');
    });

    test('seen → /', () {
      expect(initialRouteForOnboarding(seen: true), '/');
    });
  });

  group('gate end-to-end (store → route → router)', () {
    test('flag unset → initial location is /onboarding', () async {
      SharedPreferences.setMockInitialValues({});
      final seen = await SeenOnboardingStore().value();
      final loc = initialRouteForOnboarding(seen: seen);

      expect(loc, '/onboarding');
      final router = createRouter(initialLocation: loc);
      expect(router.routeInformationProvider.value.uri.path, '/onboarding');
      router.dispose();
    });

    test('flag true → initial location is /', () async {
      SharedPreferences.setMockInitialValues({'seen_onboarding': true});
      final seen = await SeenOnboardingStore().value();
      final loc = initialRouteForOnboarding(seen: seen);

      expect(loc, '/');
      final router = createRouter(initialLocation: loc);
      expect(router.routeInformationProvider.value.uri.path, '/');
      router.dispose();
    });
  });

  test('marking seen writes the flag; a fresh store then reads true', () async {
    SharedPreferences.setMockInitialValues({});

    final writer = SeenOnboardingStore();
    expect(await writer.value(), isFalse);
    await writer.markSeen();
    expect(await writer.value(), isTrue);

    // A brand-new instance (no in-memory cache) must see the persisted flag.
    final reader = SeenOnboardingStore();
    expect(await reader.value(), isTrue);
  });
}
