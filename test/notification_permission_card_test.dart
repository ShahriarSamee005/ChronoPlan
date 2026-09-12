import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/dashboard/widgets/notification_permission_card.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/notification_permission_provider.dart';

/// The card gates the app's core loop: on Android 13+ POST_NOTIFICATIONS
/// starts denied, so without this prompt every scheduled reminder is dropped
/// silently. These pin the three visibility conditions.
///
/// A real in-memory AppDatabase is used rather than a hand-built UserSetting
/// so the appOpenCount rule is exercised against the same seeded singleton row
/// the app reads at runtime.
Future<AppDatabase> _memoryDb(WidgetTester tester, {required int opens}) {
  return tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings(); // seeds the singleton settings row
    await db.updateSettings(UserSettingsCompanion(appOpenCount: Value(opens)));
    return db;
  }).then((v) => v!);
}

Future<void> _pumpCard(
  WidgetTester tester,
  AppDatabase db, {
  required bool granted,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // Stands in for the real areNotificationsEnabled() call, which would
        // reach flutter_local_notifications' method channel headless.
        notificationPermissionProvider.overrideWith((ref) async => granted),
      ],
      child: const MaterialApp(
        home: Scaffold(body: NotificationPermissionCard()),
      ),
    ),
  );
  // Let the settings stream and the permission future both resolve.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'hidden on the very first session (appOpenCount < 2), even when '
    'permission is not granted',
    (tester) async {
      final db = await _memoryDb(tester, opens: 1);

      await _pumpCard(tester, db, granted: false);

      expect(tester.takeException(), isNull);
      expect(find.text('Turn On Reminders'), findsNothing);
      expect(find.text('Enable Reminders'), findsNothing);
      expect(
        tester.getSize(find.byType(NotificationPermissionCard)),
        Size.zero,
        reason: 'a hidden card must take no vertical space in the list',
      );

      await tester.runAsync(() => db.close());
    },
  );

  testWidgets(
    'hidden once permission is granted, however many times the app has '
    'been opened',
    (tester) async {
      final db = await _memoryDb(tester, opens: 7);

      await _pumpCard(tester, db, granted: true);

      expect(tester.takeException(), isNull);
      expect(find.text('Turn On Reminders'), findsNothing);
      expect(find.text('Enable Reminders'), findsNothing);
      expect(
        tester.getSize(find.byType(NotificationPermissionCard)),
        Size.zero,
      );

      await tester.runAsync(() => db.close());
    },
  );

  testWidgets(
    'visible from the second resume onward while permission is not granted',
    (tester) async {
      final db = await _memoryDb(tester, opens: 2);

      await _pumpCard(tester, db, granted: false);

      expect(tester.takeException(), isNull);
      expect(find.text('Turn On Reminders'), findsOneWidget);
      expect(find.text('Enable Reminders'), findsOneWidget);
      expect(
        tester.getSize(find.byType(NotificationPermissionCard)).height,
        greaterThan(0),
      );

      await tester.runAsync(() => db.close());
    },
  );

  testWidgets(
    'no dismissal affordance — the card is not closeable, only satisfiable',
    (tester) async {
      final db = await _memoryDb(tester, opens: 2);

      await _pumpCard(tester, db, granted: false);

      expect(find.byIcon(Icons.close_rounded), findsNothing);

      await tester.runAsync(() => db.close());
    },
  );
}
