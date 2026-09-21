import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/ai/ai_markdown.dart';
import 'package:chronoplan/core/theme/ai_markdown_text.dart';

const _base = TextStyle(color: Colors.white, fontSize: 13.5, height: 1.5);

Future<void> _pump(WidgetTester tester, List<MdBlock> blocks,
    {Widget? trailing}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          child: AiMarkdownText(
            blocks: blocks,
            baseStyle: _base,
            trailing: trailing,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Every text leaf span under [root], flattened in paint order.
List<TextSpan> _leafSpans(InlineSpan root) {
  final out = <TextSpan>[];
  root.visitChildren((span) {
    if (span is TextSpan && span.text != null) out.add(span);
    return true;
  });
  return out;
}

Iterable<RichText> _richTexts(WidgetTester tester) =>
    tester.widgetList<RichText>(find.descendant(
        of: find.byType(AiMarkdownText), matching: find.byType(RichText)));

void main() {
  testWidgets('1. bold span renders w700, plain span does not', (tester) async {
    await _pump(tester, parseAiMarkdown('**Heavy** light'));

    final spans = _leafSpans(_richTexts(tester).single.text);
    final heavy = spans.singleWhere((s) => s.text == 'Heavy');
    final light = spans.singleWhere((s) => s.text == ' light');
    expect(heavy.style?.fontWeight, FontWeight.w700);
    expect(light.style?.fontWeight, isNot(FontWeight.w700));
    // Size and colour come from baseStyle untouched.
    expect(heavy.style?.fontSize, 13.5);
    expect(heavy.style?.color, Colors.white);
  });

  testWidgets('2. no asterisk visible for bold, italic and unmatched **',
      (tester) async {
    await _pump(
        tester, parseAiMarkdown('**bold** and *italic*\n- **half open'));

    final rendered =
        _richTexts(tester).map((r) => r.text.toPlainText()).join('\n');
    expect(rendered, contains('bold'));
    expect(rendered, contains('italic'));
    expect(rendered, contains('half open'));
    expect(rendered.contains('*'), isFalse, reason: rendered);
  });

  testWidgets('3. bullet block renders a •', (tester) async {
    await _pump(tester, parseAiMarkdown('- item'));
    expect(find.text('•'), findsOneWidget);
    expect(find.text('item', findRichText: true), findsOneWidget);
  });

  testWidgets('4. numbered block renders its marker "1."', (tester) async {
    await _pump(tester, parseAiMarkdown('1. first'));
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('•'), findsNothing);
  });

  testWidgets('5. indentLevel 1 renders further right than level 0',
      (tester) async {
    await _pump(tester, parseAiMarkdown('- outer\n  - inner'));

    final bullets = find.text('•');
    expect(bullets, findsNWidgets(2));
    final outerX = tester.getTopLeft(bullets.at(0)).dx;
    final innerX = tester.getTopLeft(bullets.at(1)).dx;
    expect(innerX - outerX, AiMarkdownText.indentStep);

    final outerText = tester.getTopLeft(find.text('outer', findRichText: true));
    final innerText = tester.getTopLeft(find.text('inner', findRichText: true));
    expect(innerText.dx, greaterThan(outerText.dx));
  });

  testWidgets('6. trailing renders inline after the LAST block\'s text',
      (tester) async {
    const key = Key('cursor');
    await _pump(tester, parseAiMarkdown('First para\n\nlast words'),
        trailing: const SizedBox(key: key, width: 2, height: 10));

    final riches = find.descendant(
        of: find.byType(AiMarkdownText), matching: find.byType(RichText));
    expect(riches, findsNWidgets(2));
    // Hosted inside the final block's RichText as a WidgetSpan…
    expect(find.descendant(of: riches.at(1), matching: find.byKey(key)),
        findsOneWidget);
    expect(find.descendant(of: riches.at(0), matching: find.byKey(key)),
        findsNothing);
    // …and positioned after the text, on its line.
    final lastRect = tester.getRect(riches.at(1));
    final cursor = tester.getRect(find.byKey(key));
    expect(cursor.left, greaterThan(lastRect.left + 20));
    expect(cursor.center.dy, inInclusiveRange(lastRect.top, lastRect.bottom));
  });

  testWidgets('7. empty blocks + trailing → trailing still renders',
      (tester) async {
    const key = Key('cursor');
    await _pump(tester, const [],
        trailing: const SizedBox(key: key, width: 2, height: 10));
    expect(find.byKey(key), findsOneWidget);
  });

  testWidgets('8. empty blocks + null trailing → no crash', (tester) async {
    await _pump(tester, const []);
    expect(tester.takeException(), isNull);
    expect(find.byType(AiMarkdownText), findsOneWidget);
    expect(_richTexts(tester), isEmpty);
  });

  testWidgets('block gaps: 8px around paragraphs, 4px between list items',
      (tester) async {
    await _pump(tester, parseAiMarkdown('Intro\n- a\n- b\nOutro'));
    double top(String t) =>
        tester.getTopLeft(find.text(t, findRichText: true)).dy;
    double bottom(String t) =>
        tester.getBottomLeft(find.text(t, findRichText: true)).dy;
    expect(top('a') - bottom('Intro'), AiMarkdownText.paragraphGap);
    expect(top('b') - bottom('a'), AiMarkdownText.listGap);
    expect(top('Outro') - bottom('b'), AiMarkdownText.paragraphGap);
  });
}
