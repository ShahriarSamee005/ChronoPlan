import 'package:flutter/material.dart';

import '../ai/ai_markdown.dart';

/// Renders blocks produced by [parseAiMarkdown].
///
/// Takes already-parsed [blocks] and never parses itself, so the caller
/// decides when parsing runs. Colour and size come entirely from [baseStyle];
/// bold spans only add `FontWeight.w700`.
///
/// [trailing] (the streaming cursor) is appended inline after the final
/// block's last character.
class AiMarkdownText extends StatelessWidget {
  final List<MdBlock> blocks;
  final TextStyle baseStyle;
  final Widget? trailing;

  const AiMarkdownText({
    super.key,
    required this.blocks,
    required this.baseStyle,
    this.trailing,
  });

  static const double bulletGutter = 18;
  static const double numberedGutter = 22;
  static const double indentStep = 16;
  static const double paragraphGap = 8;
  static const double listGap = 4;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return trailing ?? const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (i > 0) {
        final eitherParagraph = block.type == MdBlockType.paragraph ||
            blocks[i - 1].type == MdBlockType.paragraph;
        children.add(
            SizedBox(height: eitherParagraph ? paragraphGap : listGap));
      }
      children.add(
          _buildBlock(block, i == blocks.length - 1 ? trailing : null));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildBlock(MdBlock block, Widget? trailing) {
    final text = Text.rich(TextSpan(
      style: baseStyle,
      children: [
        for (final span in block.spans)
          TextSpan(
            text: span.text,
            style: span.bold
                ? baseStyle.copyWith(fontWeight: FontWeight.w700)
                : baseStyle,
          ),
        if (trailing != null)
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: trailing),
      ],
    ));

    if (block.type == MdBlockType.paragraph) return text;

    final numbered = block.type == MdBlockType.numbered;
    return Padding(
      padding: EdgeInsets.only(left: block.indentLevel * indentStep),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fixed-width gutter so wrapped lines hang clear of the marker.
          SizedBox(
            width: numbered ? numberedGutter : bulletGutter,
            child: Text(numbered ? '${block.marker}.' : '•', style: baseStyle),
          ),
          Expanded(child: text),
        ],
      ),
    );
  }
}
