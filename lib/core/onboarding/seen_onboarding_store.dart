import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sticky "has this device seen the first-run onboarding?" flag.
///
/// Cloned from [UsedAiStore]: lives in SharedPreferences (no schema change,
/// survives restarts), flips true once and never resets, and swallows any
/// storage failure so it can never block startup. Reads are cached in-memory.
class SeenOnboardingStore {
  static const _key = 'seen_onboarding';

  bool _cached = false;

  /// Whether onboarding has already been shown on this device. Returns false on
  /// any storage failure, so onboarding shows rather than being lost forever.
  Future<bool> value() async {
    if (_cached) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cached = prefs.getBool(_key) ?? false;
    } catch (e) {
      debugPrint('SeenOnboardingStore.value: $e');
      return false;
    }
    return _cached;
  }

  /// Record that onboarding has been seen. Idempotent and best-effort — a failed
  /// write is swallowed so finishing onboarding never surfaces an error.
  Future<void> markSeen() async {
    if (_cached) return;
    _cached = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (e) {
      debugPrint('SeenOnboardingStore.markSeen: $e');
    }
  }
}

final seenOnboardingStoreProvider =
    Provider<SeenOnboardingStore>((ref) => SeenOnboardingStore());

/// Pure gate: the initial router location given whether onboarding was seen.
/// Unseen → the onboarding flow; seen → the normal home. Kept pure so the
/// first-frame decision is unit-testable without pumping a router.
String initialRouteForOnboarding({required bool seen}) =>
    seen ? '/' : '/onboarding';
