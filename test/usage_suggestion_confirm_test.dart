import 'dart:async';
import 'dart:ffi';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/providers/carve_proposals_provider.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/usage_stats_provider.dart';
import 'package:chronoplan/providers/usage_suggestions_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

/// Both providers derive from `DateTime.now()` and only report hours that have
/// already elapsed today, so these tests target the hour just before now. In
/// the 00:00–00:59 window no elapsed hour exists and they skip themselves.
void main() {
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final targetHour = now.hour - 1;
  final bucketStart = today.add(Duration(hours: targetHour));

  ProviderContainer makeContainer(
    AppDatabase db,
    Map<int, List<AppUsageEntry>> hourly,
  ) =>
      ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        hourlyUsageForTodayProvider.overrideWith((ref) async => hourly),
      ]);

  /// Reads a derived AsyncValue provider once its upstream streams have emitted.
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

  test('the suggestion carries the hour\'s detected total', () async {
    if (targetHour < 0) {
      markTestSkipped('no elapsed hour exists before 01:00');
      return;
    }

    final db = AppDatabase(NativeDatabase.memory());
    final container = makeContainer(db, {
      targetHour: const [
        AppUsageEntry(
            packageName: 'com.google.android.youtube',
            appLabel: 'YouTube',
            durationMinutes: 22),
        AppUsageEntry(
            packageName: 'com.android.chrome',
            appLabel: 'Chrome',
            durationMinutes: 13),
      ],
    });
    addTearDown(container.dispose);

    final suggestions = await settle(container, usageSuggestionsProvider);

    final s = suggestions.singleWhere((s) => s.hour == targetHour);
    expect(s.totalMinutes, 35, reason: '22 + 13 detected minutes');
    expect(s.bucketStart, bucketStart);
    expect(s.bucketEnd, bucketStart.add(const Duration(hours: 1)),
        reason: 'the bucket window itself is still the full hour');

    // What confirm now writes: a top-anchored block of exactly that length.
    expect(
      s.bucketStart.add(Duration(minutes: s.totalMinutes)),
      bucketStart.add(const Duration(minutes: 35)),
    );

    await db.close();
  });

  test('a confirmed screen-time block is never offered as a carve target',
      () async {
    if (targetHour < 0) {
      markTestSkipped('no elapsed hour exists before 01:00');
      return;
    }

    const apps = [
      AppUsageEntry(
          packageName: 'com.google.android.youtube',
          appLabel: 'YouTube',
          durationMinutes: 22),
      AppUsageEntry(
          packageName: 'com.whatsapp',
          appLabel: 'WhatsApp',
          durationMinutes: 13),
    ];

    final db = AppDatabase(NativeDatabase.memory());
    // Exactly what confirm writes after this change: one 35-min usage-derived
    // block at the top of the hour, described by the top apps only.
    final written = await db.logEntriesDao.insertRetroactive(
      startTime: bucketStart,
      endTime: bucketStart.add(const Duration(minutes: 35)),
      categoryId: null,
      description: 'YouTube (22m)',
      isUsageDerived: true,
    );
    expect(written.ids.length, 1);

    final container = makeContainer(db, {targetHour: apps});
    addTearDown(container.dispose);

    final proposals = await settle(container, carveProposalsProvider);

    expect(proposals.where((p) => p.hour == targetHour), isEmpty,
        reason: 'screen time must never be carved out of screen time');

    await db.close();
  });

  test('a user-origin entry in the same shape still yields a carve proposal',
      () async {
    if (targetHour < 0) {
      markTestSkipped('no elapsed hour exists before 01:00');
      return;
    }

    const apps = [
      AppUsageEntry(
          packageName: 'com.whatsapp',
          appLabel: 'WhatsApp',
          durationMinutes: 13),
    ];

    final db = AppDatabase(NativeDatabase.memory());
    // Same window and description, but hand-logged — the guard must not fire.
    final written = await db.logEntriesDao.insertRetroactive(
      startTime: bucketStart,
      endTime: bucketStart.add(const Duration(minutes: 35)),
      categoryId: null,
      description: 'Deep work',
    );
    expect(written.ids.length, 1);

    final container = makeContainer(db, {targetHour: apps});
    addTearDown(container.dispose);

    final proposals = await settle(container, carveProposalsProvider);

    final p = proposals.singleWhere((p) => p.hour == targetHour);
    expect(p.appLabel, 'WhatsApp');
    expect(p.durationMinutes, 13);

    await db.close();
  });
}
