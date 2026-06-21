import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/notifications/notification_service.dart';
import 'providers/database_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open DB early so migrations + default seeds complete before first frame.
  final db = AppDatabase();

  // Initialise notifications (registers Android channel, sets up tap stream).
  final notificationService = NotificationService();
  await notificationService.init();

  runApp(
    ProviderScope(
      overrides: [
        // Share the single warmed-up instances across the app.
        appDatabaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const ChronoPlanApp(),
    ),
  );
}
