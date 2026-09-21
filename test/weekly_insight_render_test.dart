import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chronoplan/core/ai/groq_service.dart';
import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/theme/ai_markdown_text.dart';
import 'package:chronoplan/features/dashboard/widgets/weekly_insight_card.dart';
import 'package:chronoplan/providers/database_provider.dart';
import 'package:chronoplan/providers/settings_provider.dart';

// Weekly insight card rendering.
//
// The card returns SizedBox.shrink() when there is no Supabase session, so the
// suite initializes Supabase ONCE against an unreachable localhost URL with a
// fake local storage holding a long-lived session. Nothing here talks to the
// network: the AI service is faked, and the card's own data comes from an
// in-memory Drift database.
//
// As in the other widget tests here, DB work goes through tester.runAsync —
// drift futures don't progress inside the fake-async zone otherwise.

class _FakeGroq extends GroqService {
  _FakeGroq(this.reply);

  /// Completes with the insight text, or null for the failure path.
  final Future<String?> reply;
  int calls = 0;

  @override
  Future<String?> weeklyInsight(String weekDataJson) {
    calls++;
    return reply;
  }
}

/// Local storage that always hands back one non-expired session, so
/// `Supabase.initialize` recovers it without any network call.
class _SessionStorage extends LocalStorage {
  _SessionStorage(this.sessionJson);
  final String sessionJson;

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => true;
  @override
  Future<String?> accessToken() async => sessionJson;
  @override
  Future<void> removePersistedSession() async {}
  @override
  Future<void> persistSession(String persistSessionString) async {}
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  final _map = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _map[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      _map[key] = value;
  @override
  Future<void> removeItem({required String key}) async => _map.remove(key);
}

String _fakeSessionJson() {
  final expires =
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
          1000;
  return jsonEncode({
    'access_token': 'fake-access-token',
    'token_type': 'bearer',
    'expires_in': 86400,
    'expires_at': expires,
    'refresh_token': 'fake-refresh-token',
    'user': {
      'id': '00000000-0000-0000-0000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'test@example.com',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2020-01-01T00:00:00.000Z',
    },
  });
}

Future<AppDatabase> _dbWithOneEntry(WidgetTester tester) =>
    tester.runAsync(() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.getSettings(); // force onCreate
      // Anchored on "now", so the row always lands inside the current week.
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      await db.logEntriesDao.insertRetroactive(
        startTime: start,
        endTime: start.add(const Duration(minutes: 25)),
        categoryId: null,
        description: 'YouTube',
      );
      return db;
    }).then((v) => v!);

/// Pumps the card and lets the card's own DB reads finish. Bounded pumps only:
/// the loading state runs a CircularProgressIndicator animation.
Future<void> _pumpCard(
  WidgetTester tester,
  AppDatabase db,
  _FakeGroq fake,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      aiServiceProvider.overrideWithValue(fake),
    ],
    child: const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 360, child: WeeklyInsightCard()),
        ),
      ),
    ),
  ));
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester, {int n = 4}) async {
  for (var i = 0; i < n; i++) {
    // runAsync lets the drift/await chain inside _load() make progress.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _teardown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {});
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(() => db.close());
}

String _renderedText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join('\n');

List<TextSpan> _spansWithText(WidgetTester tester, String text) {
  final out = <TextSpan>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.text == text) out.add(s);
      return true;
    });
  }
  return out;
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://localhost:1',
      publishableKey: 'fake-anon-key',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: _SessionStorage(_fakeSessionJson()),
        pkceAsyncStorage: _MemoryPkceStorage(),
      ),
    );
    expect(Supabase.instance.client.auth.currentSession, isNotNull,
        reason: 'card renders nothing without a session');
  });

  testWidgets('1. bold insight renders w700 with no asterisks anywhere',
      (tester) async {
    final db = await _dbWithOneEntry(tester);
    final fake = _FakeGroq(
        Future.value('**Biggest sink:** YouTube at 4h. You planned 2h.'));
    await _pumpCard(tester, db, fake);

    final rendered = _renderedText(tester);
    expect(rendered.contains('*'), isFalse, reason: rendered);
    expect(rendered, contains('Biggest sink: YouTube at 4h. You planned 2h.'));
    expect(_spansWithText(tester, 'Biggest sink:').single.style?.fontWeight,
        FontWeight.w700);

    await _teardown(tester, db);
  });

  testWidgets('2. a bullet in the insight renders a • glyph', (tester) async {
    final db = await _dbWithOneEntry(tester);
    final fake = _FakeGroq(Future.value(
        'Two things stood out:\n- YouTube took 4h\n- Deep work slipped'));
    await _pumpCard(tester, db, fake);

    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('YouTube took 4h', findRichText: true), findsOneWidget);
    expect(_renderedText(tester).contains('-'), isFalse);

    await _teardown(tester, db);
  });

  testWidgets('3. style preserved: 13px, white70, height 1.6', (tester) async {
    final db = await _dbWithOneEntry(tester);
    final fake =
        _FakeGroq(Future.value('**Bold bit** and plain body text here.'));
    await _pumpCard(tester, db, fake);

    final plain = _spansWithText(tester, ' and plain body text here.').single;
    expect(plain.style?.fontSize, 13);
    expect(plain.style?.color, Colors.white70);
    expect(plain.style?.height, 1.6);
    expect(plain.style?.fontWeight, isNot(FontWeight.w700));
    // The bold span differs only in weight.
    final bold = _spansWithText(tester, 'Bold bit').single;
    expect(bold.style?.fontSize, 13);
    expect(bold.style?.color, Colors.white70);

    await _teardown(tester, db);
  });

  testWidgets('4. loading state, then the error-path copy, are unchanged',
      (tester) async {
    final db = await _dbWithOneEntry(tester);
    final completer = Completer<String?>();
    final fake = _FakeGroq(completer.future);
    await _pumpCard(tester, db, fake);

    // Still awaiting the AI call: spinner shown, no insight text, no refresh.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AiMarkdownText), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.text('Weekly Insight'), findsOneWidget);

    // A null reply is the failure path.
    completer.complete(null);
    await _frames(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(_renderedText(tester),
        contains("Couldn't generate insight. Try again."));

    await _teardown(tester, db);
  });

  testWidgets('empty week keeps its prompt copy and skips the AI call',
      (tester) async {
    final db = await tester.runAsync(() async {
      final d = AppDatabase(NativeDatabase.memory());
      await d.getSettings();
      return d;
    }).then((v) => v!);
    final fake = _FakeGroq(Future.value('should not be used'));
    await _pumpCard(tester, db, fake);

    expect(fake.calls, 0);
    expect(_renderedText(tester),
        contains('Log some entries this week to get your weekly insight.'));

    await _teardown(tester, db);
  });
}
