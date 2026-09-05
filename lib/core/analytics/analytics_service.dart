import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../providers/database_provider.dart';
import '../database/app_database.dart';
import 'analytics_guard.dart';
import 'used_ai_store.dart';

/// Fire-and-forget usage-analytics ping. COUNTERS ONLY — three numbers/booleans,
/// never any log entries, descriptions, category names, or other user content.
///
/// Writes go through the `clever-action` Edge Function (which takes user_id from
/// the validated JWT), never directly to Postgres. Every failure is swallowed:
/// the ping must never surface to the user or block the UI.
///
/// The HTTP call and the access-token lookup are `@protected` seams so tests can
/// subclass and override them without a mocking package — the same override
/// pattern used for `NotificationService`.
class AnalyticsService {
  final AppDatabase _db;
  final UsedAiStore _usedAiStore;

  AnalyticsService({
    required AppDatabase db,
    required UsedAiStore usedAiStore,
  })  : _db = db,
        _usedAiStore = usedAiStore;

  static final _pingUrl = Uri.parse(
      '${SupabaseConfig.url}/functions/v1/${SupabaseConfig.analyticsPingFunction}');

  /// Current Supabase access token, or null when there is no session.
  @protected
  String? get accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  /// POST the ping and return the HTTP status code. Sends BOTH the `apikey`
  /// (anon key) and `Authorization: Bearer` headers — a bearer-only request is
  /// rejected by the Supabase gateway before the function runs.
  @protected
  Future<int> postPing(Map<String, dynamic> body, String token) async {
    final response = await http
        .post(
          _pingUrl,
          headers: {
            'Content-Type': 'application/json',
            'apikey': SupabaseConfig.anonKey,
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    return response.statusCode;
  }

  /// Ping once per calendar day. No-op when not due, when offline/sessionless,
  /// or on any failure. Only a 2xx response advances `lastSyncedAt`, so a failed
  /// attempt retries on the next open.
  Future<void> pingIfDue() async {
    try {
      final settings = await _db.getSettings();
      final lastPing = _parseLastSynced(settings.lastSyncedAt);
      if (!shouldPing(lastPing: lastPing, now: DateTime.now())) return;

      final token = accessToken;
      if (token == null) return; // no session yet — retry next open

      final body = <String, dynamic>{
        'log_count': await _db.logEntriesDao.countAll(),
        'has_routine': (await _db.routineSlotsDao.countAll()) > 0,
        'used_ai': await _usedAiStore.value(),
      };

      final status = await postPing(body, token);
      if (status >= 200 && status < 300) {
        await _db.updateSettings(UserSettingsCompanion(
          lastSyncedAt: Value(DateTime.now().toIso8601String()),
        ));
      } else {
        debugPrint('AnalyticsService.pingIfDue: non-2xx $status');
      }
    } catch (e) {
      // Swallow everything — analytics must never reach the user or block the UI.
      debugPrint('AnalyticsService.pingIfDue: $e');
    }
  }

  /// Parse the stored ISO-8601 string; unparseable or null → null (treat as
  /// "never pinged" so the guard fires rather than getting stuck forever).
  static DateTime? _parseLastSynced(String? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }
}

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService(
    db: ref.read(appDatabaseProvider),
    usedAiStore: ref.read(usedAiStoreProvider),
  );
});
