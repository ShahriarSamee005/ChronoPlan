import 'dart:convert';

import 'package:chronoplan/core/ai/groq_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A single well-formed entry object as the model would emit it.
Map<String, dynamic> _entry({
  String description = 'Worked on report',
  String? suggestedCategory = 'Work',
  String startISO = '2026-09-02T09:00:00',
  String endISO = '2026-09-02T10:00:00',
}) =>
    {
      'description': description,
      'suggestedCategory': suggestedCategory,
      'startISO': startISO,
      'endISO': endISO,
    };

void main() {
  group('parseEntriesFromRaw', () {
    test('1. clean JSON array of 3 valid entries → 3 entries, 0 skipped', () {
      final raw = jsonEncode([
        _entry(description: 'A'),
        _entry(description: 'B'),
        _entry(description: 'C'),
      ]);

      final result = parseEntriesFromRaw(raw);

      expect(result, isNotNull);
      expect(result!.entries.length, 3);
      expect(result.skipped, 0);
      expect(result.entries.map((e) => e.description), ['A', 'B', 'C']);
    });

    test('2. one item missing startISO → 2 entries, 1 skipped', () {
      final bad = _entry(description: 'B')..remove('startISO');
      final raw = jsonEncode([_entry(description: 'A'), bad, _entry(description: 'C')]);

      final result = parseEntriesFromRaw(raw);

      expect(result, isNotNull);
      expect(result!.entries.length, 2);
      expect(result.skipped, 1);
      expect(result.entries.map((e) => e.description), ['A', 'C']);
    });

    test('3. one item with an unparseable date → 2 entries, 1 skipped', () {
      final raw = jsonEncode([
        _entry(description: 'A'),
        _entry(description: 'B', startISO: 'not-a-date'),
        _entry(description: 'C'),
      ]);

      final result = parseEntriesFromRaw(raw);

      expect(result, isNotNull);
      expect(result!.entries.length, 2);
      expect(result.skipped, 1);
      expect(result.entries.map((e) => e.description), ['A', 'C']);
    });

    test('4. one item with endISO before startISO → 2 entries, 1 skipped', () {
      final raw = jsonEncode([
        _entry(description: 'A'),
        _entry(
          description: 'B',
          startISO: '2026-09-02T10:00:00',
          endISO: '2026-09-02T09:00:00',
        ),
        _entry(description: 'C'),
      ]);

      final result = parseEntriesFromRaw(raw);

      expect(result, isNotNull);
      expect(result!.entries.length, 2);
      expect(result.skipped, 1);
      expect(result.entries.map((e) => e.description), ['A', 'C']);
    });

    test('5. one item with empty-string description → 2 entries, 1 skipped', () {
      final raw = jsonEncode([
        _entry(description: 'A'),
        _entry(description: ''),
        _entry(description: 'C'),
      ]);

      final result = parseEntriesFromRaw(raw);

      expect(result, isNotNull);
      expect(result!.entries.length, 2);
      expect(result.skipped, 1);
      expect(result.entries.map((e) => e.description), ['A', 'C']);
    });

    test('6. non-String suggestedCategory → entry kept, category null', () {
      // 42 is a valid JSON number but not a String; the entry must survive.
      final raw = jsonEncode([_entry(suggestedCategory: 'Work')..['suggestedCategory'] = 42]);

      final result = parseEntriesFromRaw(raw);

      expect(result, isNotNull);
      expect(result!.entries.length, 1);
      expect(result.skipped, 0);
      expect(result.entries.single.suggestedCategory, isNull);
    });

    test('7. JSON wrapped in ```json fences → parses fine', () {
      final raw = '```json\n${jsonEncode([_entry(description: 'A')])}\n```';

      final result = parseEntriesFromRaw(raw);

      expect(result, isNotNull);
      expect(result!.entries.length, 1);
      expect(result.skipped, 0);
      expect(result.entries.single.description, 'A');
    });

    test('8. prose containing a bracket then the array → parses fine '
        '(regression guard vs old extraction)', () {
      final array = jsonEncode([_entry(description: 'A')]);
      final raw = 'Here are your entries [times are local]: $array';

      // Prove the OLD extraction logic fails on this exact input: it sliced
      // from the first '[' to the last ']', which grabs the prose bracket too.
      final oldTrimmed = raw.trim();
      final oldJsonStr = oldTrimmed.contains('[')
          ? oldTrimmed.substring(
              oldTrimmed.indexOf('['), oldTrimmed.lastIndexOf(']') + 1)
          : oldTrimmed;
      expect(oldJsonStr.startsWith('[times are local]'), isTrue);
      expect(() => jsonDecode(oldJsonStr), throwsFormatException);

      // The new extraction parses it correctly.
      final result = parseEntriesFromRaw(raw);

      expect(result, isNotNull);
      expect(result!.entries.length, 1);
      expect(result.skipped, 0);
      expect(result.entries.single.description, 'A');
    });

    test('9. completely malformed text → null', () {
      final result = parseEntriesFromRaw('sorry, I could not do that');

      expect(result, isNull);
    });

    test('10. valid empty array → 0 entries, 0 skipped, NOT null', () {
      final result = parseEntriesFromRaw('[]');

      expect(result, isNotNull);
      expect(result!.entries, isEmpty);
      expect(result.skipped, 0);
    });
  });
}
