import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/ai/ai_markdown.dart';

MdSpan _p(String t) => MdSpan(t);
MdSpan _b(String t) => MdSpan(t, bold: true);

MdBlock _para(List<MdSpan> spans) =>
    MdBlock(type: MdBlockType.paragraph, spans: spans);

MdBlock _bullet(List<MdSpan> spans, {int indent = 0}) =>
    MdBlock(type: MdBlockType.bullet, indentLevel: indent, spans: spans);

MdBlock _num(String marker, List<MdSpan> spans, {int indent = 0}) => MdBlock(
    type: MdBlockType.numbered,
    indentLevel: indent,
    marker: marker,
    spans: spans);

/// Every `*` left in [text] must be the spaced-arithmetic exception.
bool _onlySpacedAsterisks(String text) {
  for (var i = 0; i < text.length; i++) {
    if (text[i] != '*') continue;
    final spaced = i > 0 &&
        text[i - 1] == ' ' &&
        i + 1 < text.length &&
        text[i + 1] == ' ';
    if (!spaced) return false;
  }
  return true;
}

const _debrief = '**Summary:** You logged 6h today, mostly Deep Work.\n'
    '\n'
    '## What went well\n'
    '- **Deep Work:** 3h, above plan\n'
    '- Exercise done *before* lunch\n'
    '  - 45min run\n'
    '\n'
    '**Tomorrow**\n'
    '1. Start at 09:00\n'
    '2) Cap social media at 30min\n';

void main() {
  group('basic', () {
    test('1. empty string → empty list', () {
      expect(parseAiMarkdown(''), isEmpty);
    });

    test('2. whitespace-only string → empty list', () {
      expect(parseAiMarkdown('   \n\t\n  \r\n '), isEmpty);
    });

    test('3. plain single line → one paragraph, one non-bold span', () {
      expect(parseAiMarkdown('Good day overall.'), [
        _para([_p('Good day overall.')])
      ]);
    });

    test('4. two lines, no blank between → ONE paragraph joined by a space',
        () {
      expect(parseAiMarkdown('First line\nsecond line'), [
        _para([_p('First line second line')])
      ]);
    });

    test('5. two lines with a blank between → TWO paragraphs', () {
      expect(parseAiMarkdown('First\n\nSecond'), [
        _para([_p('First')]),
        _para([_p('Second')]),
      ]);
    });

    test('CRLF line endings are handled', () {
      expect(parseAiMarkdown('One\r\n\r\n- two\r\n'), [
        _para([_p('One')]),
        _bullet([_p('two')]),
      ]);
    });

    test('runs of spaces collapse to one, content trimmed', () {
      expect(parseAiMarkdown('   lots    of     space   '), [
        _para([_p('lots of space')])
      ]);
    });
  });

  group('bold', () {
    test('6. **Hello** world → Hello bold, " world" plain', () {
      expect(parseAiMarkdown('**Hello** world').single.spans,
          [_b('Hello'), _p(' world')]);
    });

    test('7. Start **mid** end → three spans', () {
      expect(parseAiMarkdown('Start **mid** end').single.spans,
          [_p('Start '), _b('mid'), _p(' end')]);
    });

    test('8. two bold pairs on one line → four alternating spans', () {
      expect(parseAiMarkdown('**A** then **B** done').single.spans,
          [_b('A'), _p(' then '), _b('B'), _p(' done')]);
    });

    test('9. bold starting mid-word → three spans', () {
      expect(parseAiMarkdown('some**thing**here').single.spans,
          [_p('some'), _b('thing'), _p('here')]);
    });

    test('10. adjacent same-boldness spans are merged', () {
      // Italic markers split the plain text into chunks internally.
      final plain = parseAiMarkdown('a *b* c').single.spans;
      expect(plain.length, 1);
      expect(plain.single, _p('a b c'));

      // Two touching bold runs collapse into one bold span.
      final bold = parseAiMarkdown('**x****y** z').single.spans;
      expect(bold.length, 2);
      expect(bold, [_b('xy'), _p(' z')]);
    });
  });

  group('mid-stream', () {
    test('11. **What went we → one plain span, no asterisks', () {
      final spans = parseAiMarkdown('**What went we').single.spans;
      expect(spans, [_p('What went we')]);
      expect(spans.single.text.contains('*'), isFalse);
    });

    test('12. **Done** and **half → Done bold, rest plain', () {
      expect(parseAiMarkdown('**Done** and **half').single.spans,
          [_b('Done'), _p(' and half')]);
    });

    test('13. a line that is a bare "-" → no crash, no stray marker', () {
      expect(parseAiMarkdown('Plan for tomorrow\n-'), [
        _para([_p('Plan for tomorrow')])
      ]);
      expect(parseAiMarkdown('- item\n-'), [
        _bullet([_p('item')])
      ]);
      expect(parseAiMarkdown('-'), isEmpty);
      expect(parseAiMarkdown('- '), isEmpty);
    });

    test('14. a single trailing * is stripped', () {
      expect(parseAiMarkdown('Nice work*'), [
        _para([_p('Nice work')])
      ]);
      expect(parseAiMarkdown('*'), isEmpty);
    });
  });

  group('asterisk stripping', () {
    test('15. *italic* → "italic", not bold', () {
      expect(parseAiMarkdown('*italic*').single.spans, [_p('italic')]);
    });

    test('16. lone * mid-word → removed', () {
      expect(parseAiMarkdown('a*b').single.spans, [_p('ab')]);
    });

    test('17. 2 * 3 = 6 → the spaced asterisk survives', () {
      expect(parseAiMarkdown('2 * 3 = 6').single.spans, [_p('2 * 3 = 6')]);
    });

    test('18. **** → no span and no block', () {
      expect(parseAiMarkdown('****'), isEmpty);
      expect(parseAiMarkdown('- ****'), isEmpty);
    });
  });

  group('lists', () {
    test('19. "- one" / "- two" → two level-0 bullets', () {
      expect(parseAiMarkdown('- one\n- two'), [
        _bullet([_p('one')]),
        _bullet([_p('two')]),
      ]);
    });

    test('20. "* one" → bullet', () {
      expect(parseAiMarkdown('* one'), [
        _bullet([_p('one')])
      ]);
    });

    test('21. 2-space indent → indentLevel 1', () {
      expect(parseAiMarkdown('  - nested'), [
        _bullet([_p('nested')], indent: 1)
      ]);
    });

    test('22. 6-space indent → capped at indentLevel 1', () {
      expect(parseAiMarkdown('      - deep'), [
        _bullet([_p('deep')], indent: 1)
      ]);
      expect(parseAiMarkdown('\t- tabbed'), [
        _bullet([_p('tabbed')], indent: 1)
      ]);
      expect(parseAiMarkdown(' - one space'), [
        _bullet([_p('one space')])
      ]);
    });

    test('23. "1. first" → numbered, marker "1"', () {
      expect(parseAiMarkdown('1. first'), [
        _num('1', [_p('first')])
      ]);
    });

    test('24. "2) second" → numbered, marker "2"', () {
      expect(parseAiMarkdown('2) second'), [
        _num('2', [_p('second')])
      ]);
    });

    test('25. bullet containing bold', () {
      expect(parseAiMarkdown('- **Label:** value'), [
        _bullet([_b('Label:'), _p(' value')])
      ]);
    });

    test('26. paragraph, bullet, paragraph → three blocks in order', () {
      expect(parseAiMarkdown('Intro line\n- point\nOutro line'), [
        _para([_p('Intro line')]),
        _bullet([_p('point')]),
        _para([_p('Outro line')]),
      ]);
    });
  });

  group('headings', () {
    test('27. ## What went well → all-bold paragraph, no #', () {
      expect(parseAiMarkdown('## What went well'), [
        _para([_b('What went well')])
      ]);
    });

    test('28. ### **Bold heading** → all-bold, no #, no *', () {
      expect(parseAiMarkdown('### **Bold heading**'), [
        _para([_b('Bold heading')])
      ]);
      expect(parseAiMarkdown('# Mixed **part** heading'), [
        _para([_b('Mixed part heading')])
      ]);
    });

    test('a heading ends the paragraph before it', () {
      expect(parseAiMarkdown('Some text\n## Next'), [
        _para([_p('Some text')]),
        _para([_b('Next')]),
      ]);
    });
  });

  group('unsupported passthrough', () {
    test('29. table line → paragraph with text preserved', () {
      expect(parseAiMarkdown('| a | b |'), [
        _para([_p('| a | b |')])
      ]);
    });

    test('30. code fence line → paragraph', () {
      expect(parseAiMarkdown('```dart'), [
        _para([_p('```dart')])
      ]);
    });
  });

  group('invariant sweep', () {
    test('31. realistic debrief → exact blocks, no * anywhere', () {
      final blocks = parseAiMarkdown(_debrief);
      expect(blocks, [
        _para([
          _b('Summary:'),
          _p(' You logged 6h today, mostly Deep Work.'),
        ]),
        _para([_b('What went well')]),
        _bullet([_b('Deep Work:'), _p(' 3h, above plan')]),
        _bullet([_p('Exercise done before lunch')]),
        _bullet([_p('45min run')], indent: 1),
        _para([_b('Tomorrow')]),
        _num('1', [_p('Start at 09:00')]),
        _num('2', [_p('Cap social media at 30min')]),
      ]);
      for (final b in blocks) {
        for (final s in b.spans) {
          expect(s.text.contains('*'), isFalse, reason: '$s in $b');
        }
      }
    });

    test('32. streaming: every prefix parses with no stray *', () {
      for (var i = 1; i <= _debrief.length; i++) {
        final prefix = _debrief.substring(0, i);
        final blocks = parseAiMarkdown(prefix);
        for (final b in blocks) {
          expect(b.spans, isNotEmpty, reason: 'empty block for prefix $i');
          for (final s in b.spans) {
            expect(s.text, isNotEmpty, reason: 'empty span for prefix $i');
          }
          expect(_onlySpacedAsterisks(b.text), isTrue,
              reason: 'stray * at prefix $i: ${prefix.replaceAll('\n', r'\n')}'
                  ' → $b');
        }
      }
    });
  });
}
