import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _kApiBase = 'https://api.anthropic.com/v1/messages';
const _kModel = 'claude-sonnet-4-6';
const _kAnthropicVersion = '2023-06-01';

// ── Exceptions ────────────────────────────────────────────────────────────

class ClaudeOfflineException implements Exception {
  const ClaudeOfflineException();
  @override
  String toString() => 'AI coaching is unavailable offline.';
}

class ClaudeApiException implements Exception {
  final int statusCode;
  final String body;
  const ClaudeApiException(this.statusCode, this.body);
  @override
  String toString() => 'Claude API error $statusCode: $body';
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

class ClaudeService {
  final String apiKey;
  final String persona; // 'drill' | 'friendly' | 'neutral'

  const ClaudeService({required this.apiKey, required this.persona});

  // ── Connectivity guard ────────────────────────────────────────────────

  Future<bool> get isOnline async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> _assertOnline() async {
    if (!await isOnline) throw const ClaudeOfflineException();
  }

  // ── HTTP ──────────────────────────────────────────────────────────────

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': _kAnthropicVersion,
      };

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    await _assertOnline();
    final response = await http
        .post(
          Uri.parse(_kApiBase),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw ClaudeApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _extractText(Map<String, dynamic> response) {
    final content = response['content'] as List<dynamic>;
    return (content.first as Map<String, dynamic>)['text'] as String;
  }

  // ── Persona system prompt ──────────────────────────────────────────────

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

  // ── AI Features ───────────────────────────────────────────────────────

  /// Parse free-text like "meeting then coffee 20 min" into structured
  /// log entries.  Returns null on network failure (caller shows manual UI).
  Future<List<ParsedEntry>?> parseLogText(
    String text,
    DateTime anchorTime,
    List<String> knownCategories,
  ) async {
    try {
      final data = await _post({
        'model': _kModel,
        'max_tokens': 512,
        'system': 'Parse time log text into structured JSON entries. '
            'Categories available: ${knownCategories.join(', ')}. '
            'Anchor time (now): ${anchorTime.toIso8601String()}. '
            'Return ONLY a JSON array. Each object must have: '
            '"description" (string), "suggestedCategory" (string or null), '
            '"startISO" (ISO-8601), "endISO" (ISO-8601). '
            'Infer durations from text. Allocate backwards from anchor '
            'if no times are given.',
        'messages': [
          {'role': 'user', 'content': text},
        ],
      });

      final raw = _extractText(data).trim();
      // Strip any markdown code fences the model might add
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
    } on ClaudeOfflineException {
      return null;
    } catch (e) {
      debugPrint('ClaudeService.parseLogText: $e');
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
        'model': _kModel,
        'max_tokens': 20,
        'system': 'Return ONLY the single best matching category name from '
            'this list: ${categories.join(', ')}. '
            'Reply with exactly the category name, or "null" if none fits.',
        'messages': [
          {'role': 'user', 'content': description},
        ],
      });
      final text = _extractText(data).trim();
      return text.toLowerCase() == 'null' ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// Generate a 3–4 sentence weekly insight with one concrete suggestion.
  Future<String?> weeklyInsight(String weekDataJson) async {
    try {
      final data = await _post({
        'model': _kModel,
        'max_tokens': 350,
        'system': '$_personaPrompt\n\n'
            'Analyse this week\'s time-tracking data. '
            'Write 3–4 sentences in plain English covering: '
            'the biggest time sink, how actual vs planned compared, '
            'and one specific actionable suggestion for next week. '
            'Reference actual numbers from the data.',
        'messages': [
          {'role': 'user', 'content': weekDataJson},
        ],
      });
      return _extractText(data);
    } on ClaudeOfflineException {
      return null;
    } catch (e) {
      debugPrint('ClaudeService.weeklyInsight: $e');
      return null;
    }
  }

  /// True SSE token-by-token streaming debrief.
  Stream<String> debriefStreamSSE(
    List<Map<String, String>> messages,
    String dayContextPrompt,
  ) async* {
    if (!await isOnline) {
      yield 'AI coaching is unavailable offline. '
          'Reflect on your day manually using the timeline.';
      return;
    }

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse(_kApiBase));
      request.headers.addAll(_headers);
      request.body = jsonEncode({
        'model': _kModel,
        'max_tokens': 800,
        'stream': true,
        'system': '$_personaPrompt\n\n$dayContextPrompt',
        'messages': messages,
      });

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));

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
        if (data.isEmpty) continue;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          if (json['type'] == 'content_block_delta') {
            final delta = json['delta'] as Map<String, dynamic>;
            if (delta['type'] == 'text_delta') {
              yield delta['text'] as String;
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('debriefStreamSSE: $e');
      yield "Couldn't reach the AI coach. Try again in a moment.";
    } finally {
      client.close();
    }
  }

  /// Day debrief: one-shot response given conversation history + day context.
  /// Yields the response text (or an offline/error message).
  Stream<String> debriefStream(
    List<Map<String, String>> messages,
    String dayContextPrompt,
  ) async* {
    try {
      if (!await isOnline) {
        yield 'AI coaching is unavailable offline. '
            'Reflect on your day manually using the timeline.';
        return;
      }
      final data = await _post({
        'model': _kModel,
        'max_tokens': 600,
        'system': '$_personaPrompt\n\n$dayContextPrompt',
        'messages': messages,
      });
      yield _extractText(data);
    } on ClaudeApiException catch (e) {
      debugPrint('ClaudeService.debriefStream: $e');
      yield "Couldn't reach the AI coach right now. Try again in a moment.";
    } catch (e) {
      yield "Couldn't reach the AI coach right now. Try again in a moment.";
    }
  }
}
