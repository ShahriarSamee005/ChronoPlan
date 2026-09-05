import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../analytics/used_ai_store.dart';

// ── Exceptions ────────────────────────────────────────────────────────────

class GroqUnavailableException implements Exception {
  final String? detail;
  const GroqUnavailableException([this.detail]);
  @override
  String toString() =>
      'AI unavailable${detail != null ? ': $detail' : '.'}';
}

class GroqRateLimitException implements Exception {
  const GroqRateLimitException();
  @override
  String toString() => 'Daily AI limit reached. Resets at midnight UTC.';
}

// ── Data classes ──────────────────────────────────────────────────────────

class ParsedEntry {
  final String description;
  final String? suggestedCategory;
  final DateTime startTime;
  final DateTime endTime;

  const ParsedEntry({
    required this.description,
    this.suggestedCategory,
    required this.startTime,
    required this.endTime,
  });
}

// ── Service ───────────────────────────────────────────────────────────────

class GroqService {
  final String persona;

  /// Flipped true on the first successful call (any method). Optional so
  /// `const GroqService()` and existing call sites keep working untouched.
  final UsedAiStore? _usedAi;

  const GroqService({this.persona = 'friendly', UsedAiStore? usedAiStore})
      : _usedAi = usedAiStore;

  void _markAiUsed() {
    final store = _usedAi;
    if (store != null) unawaited(store.markUsed());
  }

  static const _proxyUrl =
      '${SupabaseConfig.url}/functions/v1/${SupabaseConfig.groqProxyFunction}';

  String? get _accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  String get _personaPrompt => switch (persona) {
        'drill' =>
          'You are a blunt, no-excuses productivity coach. '
              'Be direct and firm. No sugarcoating, no fluff. '
              'Hold the user accountable without being cruel.',
        'neutral' =>
          'You are a neutral data analyst. '
              'Present insights without emotional framing — '
              'just facts, patterns, and numbers.',
        _ =>
          'You are a warm, encouraging productivity coach. '
              'Be honest but supportive. Acknowledge wins, '
              'flag gaps without shame, and keep it realistic.',
      };

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ── HTTP helper ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final token = _accessToken;
    if (token == null) throw const GroqUnavailableException('No auth session');

    final response = await http
        .post(
          Uri.parse(_proxyUrl),
          headers: _headers(token),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 429) throw const GroqRateLimitException();
    if (response.statusCode != 200) {
      throw GroqUnavailableException(
          '${response.statusCode}: ${response.body}');
    }
    _markAiUsed(); // 2xx — a real AI call landed
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _extractContent(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>;
    return (choices.first as Map<String, dynamic>)['message']['content']
        as String;
  }

  // ── AI Features ───────────────────────────────────────────────────────

  /// Parse free-text like "meeting then coffee 20 min" into structured
  /// log entries.
  ///
  /// Returns `null` only on total failure (network error, non-2xx, or a
  /// response that cannot be decoded into a JSON list) — the caller shows the
  /// manual UI. On success returns the cleanly-mapped [entries] plus a
  /// [skipped] count of array items that were present but unusable; a valid
  /// empty array yields `(entries: [], skipped: 0)`, not null.
  Future<({List<ParsedEntry> entries, int skipped})?> parseLogText(
    String text,
    DateTime anchorTime,
    List<String> knownCategories,
  ) async {
    try {
      final data = await _post({
        'model': SupabaseConfig.defaultModel,
        'max_tokens': 512,
        'temperature': 0.2,
        'stream': false,
        'messages': [
          {
            'role': 'system',
            'content':
                'You must respond ONLY with valid JSON. No preamble, no explanation, no markdown code fences. Just the JSON array.\n'
                'Parse time log text into structured entries. '
                'Categories available: ${knownCategories.join(', ')}. '
                'Anchor time (now): ${anchorTime.toIso8601String()}. '
                'Return a JSON array where each object has: '
                '"description" (string), "suggestedCategory" (string matching one of the listed categories, or null), '
                '"startISO" (ISO-8601 datetime), "endISO" (ISO-8601 datetime). '
                'Infer durations from text. Allocate backwards from anchor if no times given.',
          },
          {
            'role': 'user',
            'content': '$text\n\nRespond with JSON only.',
          },
        ],
      });

      return parseEntriesFromRaw(_extractContent(data));
    } catch (e) {
      debugPrint('GroqService.parseLogText: $e');
      return null;
    }
  }

  /// Suggest the best matching category name for a log description.
  Future<String?> suggestCategory(
    String description,
    List<String> categories,
  ) async {
    try {
      final data = await _post({
        'model': SupabaseConfig.defaultModel,
        'max_tokens': 30,
        'temperature': 0.1,
        'stream': false,
        'messages': [
          {
            'role': 'system',
            'content':
                'You must respond ONLY with valid JSON. No preamble, no explanation, no markdown code fences. Just the JSON object.\n'
                'Return the single best matching category for the description. '
                'The category MUST be exactly one of: ${categories.join(', ')}. '
                'Respond with JSON: {"category": "<name>"} or {"category": null} if none fits.',
          },
          {
            'role': 'user',
            'content': '$description\n\nRespond with JSON only.',
          },
        ],
      });
      final raw = _extractContent(data).trim();
      try {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        final cat = parsed['category'];
        if (cat == null) return null;
        final name = cat as String;
        return categories.any((c) => c.toLowerCase() == name.toLowerCase())
            ? name
            : null;
      } catch (_) {
        // Fallback: treat as plain text
        final text = raw.trim();
        if (text.toLowerCase() == 'null') return null;
        return categories.any((c) => c.toLowerCase() == text.toLowerCase())
            ? text
            : null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Generate a 3–4 sentence weekly insight with one concrete suggestion.
  Future<String?> weeklyInsight(String weekDataJson) async {
    try {
      final data = await _post({
        'model': SupabaseConfig.defaultModel,
        'max_tokens': 350,
        'temperature': 0.7,
        'stream': false,
        'messages': [
          {
            'role': 'system',
            'content': '$_personaPrompt\n\n'
                'Analyse this week\'s time-tracking data. '
                'Write 3–4 sentences in plain English covering: '
                'the biggest time sink, how actual vs planned compared, '
                'and one specific actionable suggestion for next week. '
                'Reference actual numbers from the data.',
          },
          {
            'role': 'user',
            'content': weekDataJson,
          },
        ],
      });
      return _extractContent(data);
    } catch (e) {
      debugPrint('GroqService.weeklyInsight: $e');
      return null;
    }
  }

  /// Token-by-token streaming debrief using OpenAI-style SSE.
  Stream<String> debriefStreamSSE(
    List<Map<String, String>> messages,
    String dayContextPrompt,
  ) async* {
    final token = _accessToken;
    if (token == null) {
      yield 'AI coaching is unavailable. Please try again later.';
      return;
    }

    final groqMessages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '$_personaPrompt\n\n$dayContextPrompt',
      },
      ...messages
          .where((m) => m['role'] != 'system')
          .map((m) => {'role': m['role']!, 'content': m['content']!}),
    ];

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(_proxyUrl));
      request.headers.addAll(_headers(token));
      request.body = jsonEncode({
        'model': SupabaseConfig.defaultModel,
        'max_tokens': 800,
        'temperature': 0.8,
        'stream': true,
        'messages': groqMessages,
      });

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 429) {
        yield 'Daily AI limit reached. Resets at midnight UTC.';
        return;
      }
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        debugPrint('debriefStreamSSE ${response.statusCode}: $body');
        yield "Couldn't reach the AI coach. Try again in a moment.";
        return;
      }
      _markAiUsed(); // 2xx — the coach stream opened

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;
          final delta = (choices.first as Map<String, dynamic>)['delta']
              as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) yield content;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('debriefStreamSSE: $e');
      yield "Couldn't reach the AI coach. Try again in a moment.";
    } finally {
      client.close();
    }
  }
}

// ── Response parsing (pure, network-free; unit-tested directly) ─────────────

/// Decode a raw model response into structured log entries.
///
/// Returns `null` only on total failure — nothing in the response decodes into
/// a JSON list. Otherwise returns the cleanly-mapped [entries] plus a [skipped]
/// count of items that were present in the array but unusable. A response that
/// decodes to a valid empty array returns `(entries: [], skipped: 0)`.
({List<ParsedEntry> entries, int skipped})? parseEntriesFromRaw(String raw) {
  final list = _extractJsonList(raw);
  if (list == null) return null;

  final entries = <ParsedEntry>[];
  var skipped = 0;
  for (final item in list) {
    final entry = _tryMapEntry(item);
    if (entry == null) {
      skipped++;
    } else {
      entries.add(entry);
    }
  }
  return (entries: entries, skipped: skipped);
}

/// Pull the first JSON array out of a model response, tolerating reasoning-style
/// prose and code fences around it. Tries, in order: a direct decode of the
/// whole response, the content of the first fenced code block, then a
/// balanced-bracket scan of the raw text. Returns null if none yield a list.
List<dynamic>? _extractJsonList(String raw) {
  final trimmed = raw.trim();

  // 1. The whole response is the JSON.
  final direct = _tryDecodeList(trimmed);
  if (direct != null) return direct;

  // 2. Content of the first fenced block (```json … ``` or ``` … ```).
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
      .firstMatch(trimmed);
  if (fence != null) {
    final inner = _tryDecodeList(fence.group(1)!.trim());
    if (inner != null) return inner;
  }

  // 3. Balanced-bracket scan: the first '[' … matching ']' span that decodes to
  //    a list. Strengthens the old first-'[' to last-']' substring so prose that
  //    happens to contain a stray bracket cannot drag the wrong span in.
  for (var i = 0; i < trimmed.length; i++) {
    if (trimmed[i] != '[') continue;
    final end = _matchBracket(trimmed, i);
    if (end == -1) continue;
    final span = _tryDecodeList(trimmed.substring(i, end + 1));
    if (span != null) return span;
  }

  return null;
}

/// jsonDecode [s] and return it only if it decodes to a List; null on any
/// failure or non-list result.
List<dynamic>? _tryDecodeList(String s) {
  try {
    final decoded = jsonDecode(s);
    return decoded is List ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Index of the ']' matching the '[' at [start], honoring string literals and
/// nested brackets. Returns -1 if the bracket never closes.
int _matchBracket(String s, int start) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '[') {
      depth++;
    } else if (c == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Map one decoded array item to a [ParsedEntry], or null if unusable. An item
/// is usable only when it is a map with a non-empty (trimmed) `description`,
/// `startISO`/`endISO` strings that parse, and an end strictly after the start.
/// A non-string `suggestedCategory` is treated as null rather than
/// disqualifying the entry.
ParsedEntry? _tryMapEntry(dynamic item) {
  if (item is! Map<String, dynamic>) return null;

  final description = item['description'];
  if (description is! String || description.trim().isEmpty) return null;

  final startISO = item['startISO'];
  final endISO = item['endISO'];
  if (startISO is! String || endISO is! String) return null;

  final startTime = DateTime.tryParse(startISO);
  final endTime = DateTime.tryParse(endISO);
  if (startTime == null || endTime == null) return null;
  if (!endTime.isAfter(startTime)) return null;

  final category = item['suggestedCategory'];
  return ParsedEntry(
    description: description,
    suggestedCategory: category is String ? category : null,
    startTime: startTime,
    endTime: endTime,
  );
}
