import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'core/database/app_database.dart';
import 'core/notifications/notification_service.dart';
import 'core/onboarding/seen_onboarding_store.dart';
import 'providers/database_provider.dart';
import 'router.dart';

/// How long startup is willing to wait on the anonymous sign-in before giving
/// up and launching anyway. One bounded attempt — no retry.
const Duration kSignInTimeout = Duration(seconds: 4);

/// Runs the anonymous sign-in as a single bounded attempt, then returns no
/// matter what. The app launches regardless of the outcome: whether sign-in
/// succeeds, times out after [timeout], or throws. AI features simply degrade
/// to their signed-out behaviour until a later sign-in succeeds.
///
/// A hung network request would otherwise block the main thread before
/// `runApp` — so a timeout is as important as the error path here. The two
/// outcomes are logged with distinct messages so future logs are diagnosable.
@visibleForTesting
Future<void> boundedSignIn(
  Future<void> Function() signIn, {
  Duration timeout = kSignInTimeout,
}) async {
  try {
    await signIn().timeout(timeout);
  } on TimeoutException {
    debugPrint(
      'Anonymous sign-in timed out after ${timeout.inSeconds}s — '
      'launching signed out; AI features will degrade until it succeeds.',
    );
  } catch (e) {
    debugPrint('Anonymous sign-in failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Construct the DB instance eagerly, but note the connection opens lazily:
  // _openConnection() returns a LazyDatabase, so migrations + default seeds run
  // on the first query, not here at startup.
  final db = AppDatabase();

  // Initialise notifications (registers Android channel, sets up tap stream).
  final notificationService = NotificationService();
  await notificationService.init();

  // Initialise Supabase and sign in anonymously for AI features.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  final supabase = Supabase.instance.client;
  if (supabase.auth.currentUser == null) {
    // Bounded, single attempt: the app always reaches runApp below, whether
    // sign-in succeeds, times out, or fails. AI features degrade to their
    // signed-out behaviour until a sign-in succeeds. Kept before runApp so the
    // onboarding gate's startup ordering is preserved.
    await boundedSignIn(() => supabase.auth.signInAnonymously());
  }

  // Decide the first-frame route BEFORE runApp so onboarding (or the dashboard)
  // paints directly, with no flash of the wrong screen and no redirect.
  final seenOnboarding = SeenOnboardingStore();
  final seen = await seenOnboarding.value();
  final router =
      createRouter(initialLocation: initialRouteForOnboarding(seen: seen));

  runApp(
    ProviderScope(
      overrides: [
        // Share the single warmed-up instances across the app.
        appDatabaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notificationService),
        // Reuse the instance whose flag we already read, so the Provider and
        // the startup read share one cache.
        seenOnboardingStoreProvider.overrideWithValue(seenOnboarding),
      ],
      child: ChronoPlanApp(router: router),
    ),
  );
}
