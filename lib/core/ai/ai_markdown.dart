/// Pure parser for the small markdown subset the AI coach emits.
///
/// Kept free of Flutter/Drift/Riverpod imports so it is directly unit-testable
/// — see `test/ai_markdown_test.dart`.
///
/// Supported: paragraphs (consecutive lines fold into one), `- ` / `* `
/// bullets, `1.` / `1)` numbered items (both with one level of nesting), `#`
/// headings (rendered as an all-bold paragraph) and `**bold**`. Everything else
/// (tables, code fences, links, blockquotes) passes through as plain text.
///
/// Guarantee: no `*` survives into any [MdSpan.text] except a `*` with a space
/// on both sides (`2 * 3`). This holds for every prefix of a streamed
/// response, so an unterminated `**What went we` renders as plain text rather
/// than flickering asterisks, and turns bold once its closing `**` arrives.
library;

enum MdBlockType { paragraph, bullet, numbered }

class MdSpan {
  final String text;
  final bool bold;
  const MdSpan(this.text, {this.bold = false});

  @override
  bool operator ==(Object other) =>
      other is MdSpan && other.text == text && other.bold == bold;

  @override
  int get hashCode => Object.hash(text, bold);

  @override
  String toString() => 'MdSpan(${bold ? 'bold ' : ''}"$text")';
}

class MdBlock {
  final MdBlockType type;

  /// 0 or 1 only — deeper source indentation is capped at 1.
  final int indentLevel;

  /// The digits of a numbered item (e.g. `"1"`); null for other types.
  final String? marker;
  final List<MdSpan> spans;

  const MdBlock({
    required this.type,
    this.indentLevel = 0,
    this.marker,
    required this.spans,
  });

  /// The block's plain text, all spans concatenated.
  String get text => spans.map((s) => s.text).join();

  @override
  bool operator ==(Object other) {
    if (other is! MdBlock ||
        other.type != type ||
        other.indentLevel != indentLevel ||
        other.marker != marker ||
        other.spans.length != spans.length) {
      return false;
    }
    for (var i = 0; i < spans.length; i++) {
      if (other.spans[i] != spans[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(type, indentLevel, marker, Object.hashAll(spans));

  @override
  String toString() =>
      'MdBlock(${type.name}, indent: $indentLevel'
      '${marker != null ? ', marker: $marker' : ''}, $spans)';
}

final _numberedPrefix = RegExp(r'^(\d+)[.)]\s');
final _headingPrefix = RegExp(r'^#{1,6} ');

/// A line holding only a list/heading marker — a bullet or heading still
/// arriving mid-stream. Dropped so the marker never flashes up as text.
final _bareMarker = RegExp(r'^(?:-|#{1,6})$');

final _whitespaceRun = RegExp(r'\s+');

/// Parses [input] into display blocks. Never throws; returns an empty list for
/// empty or whitespace-only input, and never emits a block without text.
List<MdBlock> parseAiMarkdown(String input) {
  final blocks = <MdBlock>[];
  final paragraphLines = <List<MdSpan>>[];

  void add(MdBlockType type, List<MdSpan> spans,
      {int indentLevel = 0, String? marker}) {
    final normalized = _normalize(spans);
    if (normalized.isEmpty) return;
    blocks.add(MdBlock(
      type: type,
      indentLevel: indentLevel,
      marker: marker,
      spans: normalized,
    ));
  }

  void flushParagraph() {
    if (paragraphLines.isEmpty) return;
    final joined = <MdSpan>[];
    for (final line in paragraphLines) {
      if (joined.isNotEmpty) joined.add(const MdSpan(' '));
      joined.addAll(line);
    }
    paragraphLines.clear();
    add(MdBlockType.paragraph, joined);
  }

  for (var line in input.split('\n')) {
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

    if (line.trim().isEmpty) {
      flushParagraph();
      continue;
    }

    final body = line.trimLeft();
    final lead = line.substring(0, line.length - body.length);
    final indent = (lead.contains('\t') || lead.length >= 2) ? 1 : 0;

    if (body.startsWith('- ') || body.startsWith('* ')) {
      flushParagraph();
      add(MdBlockType.bullet, _inline(body.substring(2)), indentLevel: indent);
      continue;
    }

    final numbered = _numberedPrefix.firstMatch(body);
    if (numbered != null) {
      flushParagraph();
      add(MdBlockType.numbered, _inline(body.substring(numbered.end)),
          indentLevel: indent, marker: numbered.group(1));
      continue;
    }

    final heading = _headingPrefix.firstMatch(body);
    if (heading != null) {
      flushParagraph();
      add(
        MdBlockType.paragraph,
        [
          for (final s in _inline(body.substring(heading.end)))
            MdSpan(s.text, bold: true),
        ],
      );
      continue;
    }

    if (_bareMarker.hasMatch(body.trimRight())) {
      flushParagraph();
      continue;
    }

    paragraphLines.add(_inline(body));
  }
  flushParagraph();
  return blocks;
}

/// Inline pass over one line's content: resolves `**` pairs into bold spans
/// and strips every other `*` except one with a space on both sides.
///
/// `**` markers pair up in order; an odd trailing one (a bold still streaming
/// in) is dropped and its text stays plain.
List<MdSpan> _inline(String content) {
  final s = content.trim().replaceAll(_whitespaceRun, ' ');

  // Tokens: String text chunks, or null for a `**` marker.
  final tokens = <String?>[];
  final text = StringBuffer();
  void flushText() {
    if (text.isEmpty) return;
    tokens.add(text.toString());
    text.clear();
  }

  var doubles = 0;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c != '*') {
      text.write(c);
      i++;
    } else if (i + 1 < s.length && s[i + 1] == '*') {
      flushText();
      tokens.add(null);
      doubles++;
      i += 2;
    } else {
      // Single `*`: italics marker or stray — dropped unless it is spaced
      // arithmetic like `2 * 3`.
      final spaced =
          i > 0 && s[i - 1] == ' ' && i + 1 < s.length && s[i + 1] == ' ';
      if (spaced) text.write('*');
      i++;
    }
  }
  flushText();

  final matched = doubles - doubles % 2;
  final spans = <MdSpan>[];
  var bold = false;
  var seen = 0;
  for (final t in tokens) {
    if (t == null) {
      if (seen < matched) bold = !bold;      seen++;
    } else {
      spans.add(MdSpan(t, bold: bold));
    }
  }
  return spans;
}

/// Collapses whitespace runs (including across span boundaries), trims the
/// ends, drops empty spans and merges neighbours of equal boldness.
List<MdSpan> _normalize(List<MdSpan> spans) {
  final out = <MdSpan>[];
  var prevSpace = true; // true at the start so leading space is trimmed
  for (final span in spans) {
    final buf = StringBuffer();
    for (final ch in span.text.split('')) {
      if (ch.trim().isEmpty) {
        if (!prevSpace) buf.write(' ');
        prevSpace = true;
      } else {
        buf.write(ch);
        prevSpace = false;
      }
    }
    if (buf.isEmpty) continue;
    final chunk = buf.toString();
    // A lone space carries no boldness of its own — fold it into its
    // neighbour rather than opening a new span.
    if (out.isNotEmpty && (out.last.bold == span.bold || chunk == ' ')) {
      out.last = MdSpan(out.last.text + chunk, bold: out.last.bold);
    } else {
      out.add(MdSpan(chunk, bold: span.bold));
    }
  }
  // Trim trailing whitespace; an all-space last span disappears entirely.
  while (out.isNotEmpty && out.last.text.endsWith(' ')) {
    final trimmed = out.last.text.trimRight();
    if (trimmed.isEmpty) {
      out.removeLast();
    } else {
      out.last = MdSpan(trimmed, bold: out.last.bold);
    }
  }
  return out;
}
