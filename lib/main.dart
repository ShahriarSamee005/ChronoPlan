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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open DB early so migrations + default seeds complete before first frame.
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
    try {
      await supabase.auth.signInAnonymously();
    } catch (e) {
      // Offline on first launch — AI features will fail gracefully.
      debugPrint('Anonymous sign-in failed: $e');
    }
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
