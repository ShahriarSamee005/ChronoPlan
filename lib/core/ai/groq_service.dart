import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

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

  const GroqService({this.persona = 'friendly'});

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
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _extractContent(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>;
    return (choices.first as Map<String, dynamic>)['message']['content']
        as String;
  }

  // ── AI Features ───────────────────────────────────────────────────────

  /// Parse free-text like "meeting then coffee 20 min" into structured
  /// log entries. Returns null on failure (caller shows manual UI).
  Future<List<ParsedEntry>?> parseLogText(
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

      final raw = _extractContent(data).trim();
      final jsonStr = raw.contains('[')
          ? raw.substring(raw.indexOf('['), raw.lastIndexOf(']') + 1)
          : raw;
      final list = jsonDecode(jsonStr) as List<dynamic>;

      return list.map((item) {
        final m = item as Map<String, dynamic>;
        return ParsedEntry(
          description: m['description'] as String,
          suggestedCategory: m['suggestedCategory'] as String?,
          startTime: DateTime.parse(m['startISO'] as String),
          endTime: DateTime.parse(m['endISO'] as String),
        );
      }).toList();
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
