import 'dart:async';
import 'dart:ffi';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/dashboard/widgets/usage_suggestions_card.dart';
import 'package:chronoplan/providers/carve_proposals_provider.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/pending_reconciliation_provider.dart';
import 'package:chronoplan/providers/usage_stats_provider.dart';
import 'package:chronoplan/providers/usage_suggestions_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

/// Both source providers read `DateTime.now()` and only report ELAPSED hours,
/// so these tests target the hours just before now and skip themselves in the
/// early-morning window where not enough elapsed hours exist.
void main() {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime startOfHour(int hour) => today.add(Duration(hours: hour));

  AppUsageEntry app(String label, int minutes) => AppUsageEntry(
        packageName: 'com.example.${label.toLowerCase()}',
        appLabel: label,
        durationMinutes: minutes,
      );

  ProviderContainer makeContainer(
    AppDatabase db,
    Map<int, List<AppUsageEntry>> hourly,
  ) =>
      ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        usagePermissionProvider.overrideWith((ref) async => true),
        hourlyUsageForTodayProvider.overrideWith((ref) async => hourly),
      ]);

  /// Waits for one derived AsyncValue provider to leave its loading state.
  Future<T> settle<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
  ) {
    final completer = Completer<T>();
    final sub = container.listen<AsyncValue<T>>(
      provider,
      (_, next) {
        if (!next.isLoading && !completer.isCompleted) {
          completer.complete(next.requireValue);
        }
      },
      fireImmediately: true,
    );
    final first = container.read(provider);
    if (!first.isLoading && !completer.isCompleted) {
      completer.complete(first.requireValue);
    }
    return completer.future
        .timeout(const Duration(seconds: 5))
        .whenComplete(sub.close);
  }

  /// Settles both sources, then reads the count they feed.
  Future<int> readCount(ProviderContainer container) async {
    await settle(container, usageSuggestionsProvider);
    await settle(container, carveProposalsProvider);
    return container.read(pendingReconciliationCountProvider);
  }

  test('counts empty-hour suggestions and carve hours together', () async {
    if (now.hour < 2) {
      markTestSkipped('needs two elapsed hours today');
      return;
    }
    final suggestionHour = now.hour - 1;
    final carveHour = now.hour - 2;

    final db = AppDatabase(NativeDatabase.memory());
    // carveHour is already logged by hand → its usage becomes a carve proposal.
    await db.logEntriesDao.insertRetroactive(
      startTime: startOfHour(carveHour),
      endTime: startOfHour(carveHour).add(const Duration(minutes: 40)),
      categoryId: null,
      description: 'Deep work',
    );
    // suggestionHour is left empty → it becomes an empty-hour suggestion.

    final container = makeContainer(db, {
      suggestionHour: [app('YouTube', 35)],
      carveHour: [app('WhatsApp', 18)],
    });
    addTearDown(container.dispose);

    expect(await settle(container, usageSuggestionsProvider), hasLength(1));
    expect(await settle(container, carveProposalsProvider), hasLength(1));
    expect(await readCount(container), 2,
        reason: '1 empty-hour suggestion + 1 logged hour with carves');

    await db.close();
  });

  test('several carves on one logged hour count as a single item', () async {
    if (now.hour < 1) {
      markTestSkipped('needs one elapsed hour today');
      return;
    }
    final carveHour = now.hour - 1;

    final db = AppDatabase(NativeDatabase.memory());
    await db.logEntriesDao.insertRetroactive(
      startTime: startOfHour(carveHour),
      endTime: startOfHour(carveHour).add(const Duration(minutes: 40)),
      categoryId: null,
      description: 'Deep work',
    );

    final container = makeContainer(db, {
      carveHour: [app('WhatsApp', 18), app('YouTube', 12)],
    });
    addTearDown(container.dispose);

    final proposals = await settle(container, carveProposalsProvider);
    expect(proposals, hasLength(2), reason: 'two apps propose separately');
    expect(proposals.map((p) => p.loggedEntry.id).toSet(), hasLength(1));

    expect(await readCount(container), 1,
        reason: 'one hour to reconcile, however many apps it lists');

    await db.close();
  });

  test('nothing detected → count is zero', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = makeContainer(db, const {});
    addTearDown(container.dispose);

    expect(await readCount(container), 0);

    await db.close();
  });

  testWidgets('the card stays visible with carves but zero suggestions',
      (tester) async {
    if (now.hour < 1) {
      markTestSkipped('needs one elapsed hour today');
      return;
    }
    final carveHour = now.hour - 1;

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = makeContainer(db, {
      carveHour: [app('WhatsApp', 18)],
    });
    addTearDown(container.dispose);

    // The DB writes and the provider streams are real async work, so they must
    // run outside the widget tester's fake-async zone or they never complete.
    await tester.runAsync(() async {
      await db.logEntriesDao.insertRetroactive(
        startTime: startOfHour(carveHour),
        endTime: startOfHour(carveHour).add(const Duration(minutes: 40)),
        categoryId: null,
        description: 'Deep work',
      );
      // Only a carve is pending — no empty-hour suggestion exists.
      expect(await settle(container, usageSuggestionsProvider), isEmpty);
      expect(await settle(container, carveProposalsProvider), hasLength(1));
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: UsageSuggestionsCard()),
          ),
        ),
      ),
    );
    await tester.pump();

    // The card rendered, with the carve as a row naming the app, its minutes,
    // and the source hour.
    expect(find.text('Screen Time Suggestions'), findsOneWidget);
    expect(find.textContaining('WhatsApp 18m'), findsOneWidget);
    expect(find.textContaining('Split out of "Deep work"'), findsOneWidget);
    // Header pill shows the shared count.
    expect(find.text('1'), findsOneWidget);
    // Suggestion-row styling, not the old boxed group.
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('two apps in one logged hour render as two separate rows',
      (tester) async {
    if (now.hour < 1) {
      markTestSkipped('needs one elapsed hour today');
      return;
    }
    final carveHour = now.hour - 1;

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = makeContainer(db, {
      carveHour: [app('WhatsApp', 18), app('YouTube', 12)],
    });
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await db.logEntriesDao.insertRetroactive(
        startTime: startOfHour(carveHour),
        endTime: startOfHour(carveHour).add(const Duration(minutes: 40)),
        categoryId: null,
        description: 'Deep work',
      );
      expect(await settle(container, carveProposalsProvider), hasLength(2));
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: UsageSuggestionsCard()),
          ),
        ),
      ),
    );
    await tester.pump();

    // One row per app — not one grouped block for the hour.
    expect(find.textContaining('WhatsApp 18m'), findsOneWidget);
    expect(find.textContaining('YouTube 12m'), findsOneWidget);
    expect(find.text('Confirm'), findsNWidgets(2));
    expect(find.text('Dismiss'), findsNWidgets(2));
    // Still ONE thing to reconcile as far as the badge is concerned.
    expect(find.text('1'), findsOneWidget);
  });
}
