import 'package:chronoplan/core/onboarding/seen_onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Isolated in its own file (its own test isolate) so that deliberately NOT
/// installing a SharedPreferences mock — which makes the platform channel throw
/// MissingPluginException — cannot poison the prefs singleton for the other
/// onboarding tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a SharedPreferences failure is swallowed — value() returns false, '
      'never throws, so startup is not blocked', () async {
    // No SharedPreferences.setMockInitialValues here: getInstance() throws.
    final store = SeenOnboardingStore();

    // A throw here would fail the test; the store must swallow it and return
    // false so startup is never blocked.
    final result = await store.value();
    expect(result, isFalse, reason: 'unavailable storage must read as "unseen"');
  });
}
