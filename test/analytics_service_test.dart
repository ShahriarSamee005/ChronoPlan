import 'dart:ffi';

import 'package:chronoplan/core/analytics/analytics_service.dart';
import 'package:chronoplan/core/analytics/used_ai_store.dart';
import 'package:chronoplan/core/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';

/// Real service with the two network seams overridden — no mocking package,
/// same pattern as `_FakeNotificationService`. `accessToken` and `postPing` are
/// `@protected` on the base class, so this exercises the REAL `pingIfDue` logic
/// (guard, ordering, the 2xx-only write) against fakes.
class _FakeAnalyticsService extends AnalyticsService {
  _FakeAnalyticsService(AppDatabase db, UsedAiStore store)
      : super(db: db, usedAiStore: store);

  String? token = 'fake-access-token';
  int statusToReturn = 200;
  bool throwOnPost = false;

  int postAttempts = 0;
  Map<String, dynamic>? lastBody;

  @override
  String? get accessToken => token;

  @override
  Future<int> postPing(Map<String, dynamic> body, String tok) async {
    postAttempts++;
    lastBody = body;
    if (throwOnPost) throw Exception('network boom');
    return statusToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppDatabase> freshDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings(); // triggers onCreate → seeds the settings row
    return db;
  }

  Future<void> setLastSynced(AppDatabase db, String? iso) => db.updateSettings(
        UserSettingsCompanion(lastSyncedAt: Value(iso)),
      );

  Future<String?> readLastSynced(AppDatabase db) async =>
      (await db.getSettings()).lastSyncedAt;

  test('lastSyncedAt earlier today → no HTTP attempt, no write', () async {
    final db = await freshDb();
    final now = DateTime.now();
    final earlierToday = DateTime(now.year, now.month, now.day); // midnight today
    await setLastSynced(db, earlierToday.toIso8601String());

    final svc = _FakeAnalyticsService(db, UsedAiStore());
    await svc.pingIfDue();

    expect(svc.postAttempts, 0, reason: 'guard should short-circuit');
    expect(await readLastSynced(db), earlierToday.toIso8601String(),
        reason: 'lastSyncedAt must be untouched when not due');
    await db.close();
  });

  test('lastSyncedAt null → ping attempted with counters-only body', () async {
    final db = await freshDb();
    final svc = _FakeAnalyticsService(db, UsedAiStore());

    await svc.pingIfDue();

    expect(svc.postAttempts, 1);
    // The whole point of the review: NOTHING but the three counters ships.
    expect(svc.lastBody!.keys.toSet(), {'log_count', 'has_routine', 'used_ai'});
    expect(svc.lastBody!['log_count'], isA<int>());
    expect(svc.lastBody!['has_routine'], isA<bool>());
    expect(svc.lastBody!['used_ai'], isA<bool>());
    await db.close();
  });

  test('lastSyncedAt yesterday → ping attempted', () async {
    final db = await freshDb();
    final now = DateTime.now();
    final yesterday =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    await setLastSynced(db, yesterday.toIso8601String());

    final svc = _FakeAnalyticsService(db, UsedAiStore());
    await svc.pingIfDue();

    expect(svc.postAttempts, 1);
    await db.close();
  });

  test('lastSyncedAt unparseable garbage → ping attempted (never stuck)',
      () async {
    final db = await freshDb();
    await setLastSynced(db, 'not-a-real-date');

    final svc = _FakeAnalyticsService(db, UsedAiStore());
    await svc.pingIfDue();

    expect(svc.postAttempts, 1, reason: 'garbage must be treated as null → ping');
    await db.close();
  });

  test('2xx success writes lastSyncedAt as a parseable ISO string for today',
      () async {
    final db = await freshDb();
    final svc = _FakeAnalyticsService(db, UsedAiStore())..statusToReturn = 200;

    await svc.pingIfDue();

    final written = await readLastSynced(db);
    expect(written, isNotNull);
    final parsed = DateTime.parse(written!); // must not throw
    final now = DateTime.now();
    expect(DateTime(parsed.year, parsed.month, parsed.day),
        DateTime(now.year, now.month, now.day));
    await db.close();
  });

  test('POST throws → does NOT write lastSyncedAt and does NOT rethrow',
      () async {
    final db = await freshDb();
    final svc = _FakeAnalyticsService(db, UsedAiStore())..throwOnPost = true;

    // Must not throw out of pingIfDue.
    await svc.pingIfDue();

    expect(svc.postAttempts, 1, reason: 'the attempt was made');
    expect(await readLastSynced(db), isNull,
        reason: 'a failed ping must retry next open');
    await db.close();
  });

  test('non-2xx → does NOT write lastSyncedAt', () async {
    final db = await freshDb();
    final svc = _FakeAnalyticsService(db, UsedAiStore())..statusToReturn = 500;

    await svc.pingIfDue();

    expect(svc.postAttempts, 1);
    expect(await readLastSynced(db), isNull);
    await db.close();
  });

  test('no session (null token) → returns early, no attempt, no write',
      () async {
    final db = await freshDb();
    final svc = _FakeAnalyticsService(db, UsedAiStore())..token = null;

    await svc.pingIfDue();

    expect(svc.postAttempts, 0, reason: 'must not POST without a session');
    expect(await readLastSynced(db), isNull,
        reason: 'must not advance lastSyncedAt without a session');
    await db.close();
  });
}
