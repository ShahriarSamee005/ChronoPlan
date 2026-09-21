import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/ai/groq_service.dart';
import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/core/theme/ai_markdown_text.dart';
import 'package:chronoplan/core/theme/glass_card.dart';
import 'package:chronoplan/features/debrief/debrief_screen.dart';
import 'package:chronoplan/providers/categories_provider.dart';
import 'package:chronoplan/providers/intention_tasks_provider.dart';
import 'package:chronoplan/providers/intentions_provider.dart';
import 'package:chronoplan/providers/log_entries_provider.dart';
import 'package:chronoplan/providers/routine_provider.dart';
import 'package:chronoplan/providers/settings_provider.dart';

// Debrief bubble rendering + streaming throttle.
//
// The AI service is faked so each debriefStreamSSE call hands back a
// StreamController the test drives token by token. Data providers are
// overridden with fixed values — no database needed.
//
// The streaming bubble carries _BlinkingCursor (repeat(reverse: true)), so
// pumpAndSettle never terminates: bounded pumps only.

class _FakeGroq extends GroqService {
  _FakeGroq();

  final streams = <StreamController<String>>[];

  @override
  Stream<String> debriefStreamSSE(
    List<Map<String, String>> messages,
    String dayContextPrompt,
  ) {
    final c = StreamController<String>();
    streams.add(c);
    return c.stream;
  }
}

Future<_FakeGroq> _pumpDebrief(WidgetTester tester) async {
  final fake = _FakeGroq();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      aiServiceProvider.overrideWithValue(fake),
      logEntriesForDayProvider
          .overrideWith((ref, day) => Stream.value(const <LogEntry>[])),
      categoriesProvider
          .overrideWith((ref) => Stream.value(const <Category>[])),
      allRoutineSlotsProvider
          .overrideWith((ref) => Stream.value(const <RoutineSlot>[])),
      todayIntentionProvider.overrideWith((ref) => Stream.value(null)),
      dayTasksProvider
          .overrideWith((ref, day) => Stream.value(const <IntentionTask>[])),
      taskCountsProvider.overrideWith((ref, day) async => (0, 0)),
    ],
    child: const MaterialApp(home: DebriefScreen()),
  ));
  await _frames(tester);
  expect(fake.streams, hasLength(1), reason: 'opening debrief should start');
  return fake;
}

Future<void> _frames(WidgetTester tester, {int n = 6}) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Past the throttle window, so any pending tick has fired.
Future<void> _pastThrottle(WidgetTester tester) async {
  await tester.pump(kStreamThrottle + const Duration(milliseconds: 10));
  await _frames(tester, n: 2);
}

/// Disposes the screen so its hour timer, throttle timer and subscription go.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 16));
}

/// Plain text of every assistant bubble (each AiMarkdownText), in order.
List<String> _assistantTexts(WidgetTester tester) => [
      for (final md in find.byType(AiMarkdownText).evaluate())
        tester
            .widgetList<RichText>(find.descendant(
                of: find.byWidget(md.widget), matching: find.byType(RichText)))
            .map((r) => r.text.toPlainText())
            .join('\n'),
    ];

String _allRenderedText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join('\n');

List<String> _tokens(int n, [int from = 0]) =>
    [for (var i = from; i < from + n; i++) 'w$i '];

void main() {
  group('bubble wiring', () {
    testWidgets('9. assistant **Bold** renders w700 with no asterisks',
        (tester) async {
      final fake = await _pumpDebrief(tester);
      fake.streams.single.add('**Bold** and more');
      await fake.streams.single.close();
      await _pastThrottle(tester);

      // Asserted on everything painted, independent of widget type, so a
      // plain-Text bubble fails here for the real reason.
      final rendered = _allRenderedText(tester);
      expect(rendered.contains('*'), isFalse, reason: rendered);
      expect(rendered, contains('Bold and more'));

      final boldSpans = <TextSpan>[];
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((s) {
          if (s is TextSpan && s.text == 'Bold') boldSpans.add(s);
          return true;
        });
      }
      expect(boldSpans.single.style?.fontWeight, FontWeight.w700);
      expect(_assistantTexts(tester), ['Bold and more']);

      await _teardown(tester);
    });

    testWidgets('10. user **text** is shown literally, not parsed',
        (tester) async {
      final fake = await _pumpDebrief(tester);
      fake.streams.single.add('Opening.');
      await fake.streams.single.close();
      await _pastThrottle(tester);

      await tester.enterText(find.byType(TextField), 'Why **text** here');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await _frames(tester);

      expect(fake.streams, hasLength(2));
      expect(find.text('Why **text** here'), findsOneWidget);
      // Still literal while the reply streams in.
      fake.streams.last.add('Because.');
      await fake.streams.last.close();
      await _pastThrottle(tester);
      expect(find.text('Why **text** here'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('11. assistant bubble width is capped', (tester) async {
      final fake = await _pumpDebrief(tester);
      fake.streams.single.add(List.filled(300, 'word').join(' '));
      await fake.streams.single.close();
      await _pastThrottle(tester);

      final screenW = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      final cap = screenW * kDebriefBubbleMaxWidthFraction;
      final bubble = find.ancestor(
          of: find.byType(AiMarkdownText), matching: find.byType(GlassCard));
      final w = tester.getSize(bubble).width;
      expect(w, lessThanOrEqualTo(cap + 0.01));
      // The long line genuinely fills out to the cap (not trivially narrow).
      expect(w, greaterThan(cap - 40));

      await _teardown(tester);
    });
  });

  group('streaming', () {
    testWidgets('12. final flush: displayed text equals every token',
        (tester) async {
      final fake = await _pumpDebrief(tester);
      final c = fake.streams.single;
      final tokens = _tokens(30);

      for (final t in tokens.take(15)) {
        c.add(t);
      }
      await _pastThrottle(tester); // one throttled tick shows the first half
      for (final t in tokens.skip(15)) {
        c.add(t);
      }
      await c.close(); // the second half lands inside a pending window
      await _pastThrottle(tester);

      expect(_assistantTexts(tester), [tokens.join().trim()]);
      await _teardown(tester);
    });

    testWidgets('13. flush on error keeps everything received so far',
        (tester) async {
      final fake = await _pumpDebrief(tester);
      final c = fake.streams.single;
      final tokens = _tokens(20);

      for (final t in tokens.take(10)) {
        c.add(t);
      }
      await _pastThrottle(tester);
      for (final t in tokens.skip(10)) {
        c.add(t);
      }
      c.addError(Exception('connection dropped'));
      await _pastThrottle(tester);

      expect(_assistantTexts(tester), [tokens.join().trim()]);
      // The stream is finished: input re-enabled, no cursor left streaming.
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await _teardown(tester);
    });

    testWidgets('14. 10 tokens inside one window rebuild the screen < 10 times',
        (tester) async {
      final fake = await _pumpDebrief(tester);
      final c = fake.streams.single;

      var rebuilds = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is DebriefScreen) rebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      // 10 tokens, a frame after each, all inside one 50 ms window. Unthrottled
      // code would setState + rebuild on every one of these frames.
      for (final t in _tokens(10)) {
        c.add(t);
        await tester.pump(const Duration(milliseconds: 4));
      }
      expect(rebuilds, lessThan(10));
      expect(rebuilds, 0, reason: 'no tick has fired yet inside the window');

      // Once the window closes, exactly one rebuild shows all ten tokens.
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(rebuilds, 1);
      expect(_assistantTexts(tester).single, startsWith(_tokens(10).join().trim()));

      debugOnRebuildDirtyWidget = null;
      await c.close();
      await _pastThrottle(tester);
      await _teardown(tester);
    });
  });
}
