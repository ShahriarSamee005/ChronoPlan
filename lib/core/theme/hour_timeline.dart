import 'package:flutter/material.dart';

import '../../features/day_view/hour_row_planner.dart';
import 'glass_card.dart';

/// Height of one lane inside an hour row. Tall enough that a 15-minute block
/// still has room for its label.
const double _laneHeight = 52.0;

/// Floor width for very short slivers so they stay tappable. A 15-minute block
/// sits well above this at its true width, so the layout stays truthful.
const double _minSegWidth = 48.0;

const double _gutterWidth = 52.0;

/// A reusable 24-row per-hour timeline: one row per hour, variable row height
/// (`_laneHeight * laneCount`), a left hour-label gutter, and a block track that
/// positions the planned [HourSegment]s. The generic scaffolding lives here; the
/// screen-specific per-row layers (routine overlay edge, now-line, …) are passed
/// in through [backgroundLayers] / [foregroundLayers], and the entry lookups
/// (colour, label) and interactions come in as callbacks.
///
/// This is a pure move-and-parameterize of the Day View timeline: the geometry
/// math, constants, z-order, and widget keys are preserved exactly so both Day
/// View and (later) the Routine screen can draw through it.
class HourTimeline extends StatelessWidget {
  final List<List<HourSegment>> rows;
  final ScrollController scrollController;
  final Color Function(int id) segmentColor;
  final String Function(int id) segmentLabel;
  final void Function(int id) onSegmentTap;
  final void Function(int id) onSegmentDelete;
  final bool swipeEnabled;
  final void Function(int hour)? onEmptyHourTap;
  final List<Widget> Function(int hour, double trackWidth, double rowHeight)?
      backgroundLayers;
  final List<Widget> Function(int hour, double trackWidth, double rowHeight)?
      foregroundLayers;

  const HourTimeline({
    super.key,
    required this.rows,
    required this.scrollController,
    required this.segmentColor,
    required this.segmentLabel,
    required this.onSegmentTap,
    required this.onSegmentDelete,
    required this.swipeEnabled,
    this.onEmptyHourTap,
    this.backgroundLayers,
    this.foregroundLayers,
  });

  /// The planner guarantees one uniform `laneCount` across an hour's segments.
  static int _laneCountOf(List<List<HourSegment>> rows, int hour) =>
      rows[hour].isEmpty ? 1 : rows[hour].first.laneCount;

  /// Height of the row for [hour], exposed so callers can compute scroll
  /// offsets against the same variable-height layout this widget lays out.
  static double rowHeight(List<List<HourSegment>> rows, int hour) =>
      _laneHeight * _laneCountOf(rows, hour);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      // Rows vary in height with their lane count, so no itemExtent.
      itemCount: 24,
      padding: const EdgeInsets.only(bottom: 100),
      itemBuilder: (_, h) => _HourRow(
        hour: h,
        segments: rows[h],
        height: rowHeight(rows, h),
        segmentColor: segmentColor,
        segmentLabel: segmentLabel,
        onSegmentTap: onSegmentTap,
        onSegmentDelete: onSegmentDelete,
        swipeEnabled: swipeEnabled,
        onEmptyHourTap: onEmptyHourTap,
        backgroundLayers: backgroundLayers,
        foregroundLayers: foregroundLayers,
      ),
    );
  }
}

class _HourRow extends StatelessWidget {
  final int hour;
  final List<HourSegment> segments;
  final double height;
  final Color Function(int id) segmentColor;
  final String Function(int id) segmentLabel;
  final void Function(int id) onSegmentTap;
  final void Function(int id) onSegmentDelete;
  final bool swipeEnabled;
  final void Function(int hour)? onEmptyHourTap;
  final List<Widget> Function(int hour, double trackWidth, double rowHeight)?
      backgroundLayers;
  final List<Widget> Function(int hour, double trackWidth, double rowHeight)?
      foregroundLayers;

  const _HourRow({
    required this.hour,
    required this.segments,
    required this.height,
    required this.segmentColor,
    required this.segmentLabel,
    required this.onSegmentTap,
    required this.onSegmentDelete,
    required this.swipeEnabled,
    required this.onEmptyHourTap,
    required this.backgroundLayers,
    required this.foregroundLayers,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _gutterWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 6, top: 2),
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Hour divider, painted inside the Stack so it costs no
                    // layout height (the scroll offset math depends on that).
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 0.5,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    // An empty hour is only tappable when a caller opts in; Day
                    // View passes null, so this element is absent there.
                    if (onEmptyHourTap != null && segments.isEmpty)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onEmptyHourTap!(hour),
                        ),
                      ),
                    // Caller-supplied background layers (e.g. the routine edge),
                    // behind the segments.
                    if (backgroundLayers != null)
                      ...backgroundLayers!(hour, w, height),
                    for (final seg in segments) ..._segment(seg, w),
                    // Caller-supplied foreground layers (e.g. the now-line),
                    // above the segments.
                    if (foregroundLayers != null)
                      ...foregroundLayers!(hour, w, height),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  List<Widget> _segment(HourSegment seg, double w) {
    final color = segmentColor(seg.entryId);
    final label = segmentLabel(seg.entryId);

    var left = seg.startMin / 60 * w;
    var width = (seg.endMin - seg.startMin) / 60 * w;
    if (width < _minSegWidth) width = _minSegWidth;
    if (width > w) width = w;
    // A floored sliver near the right edge would overflow — shift it back in.
    if (left + width > w) left = w - width;
    if (left < 0) left = 0;

    // Round only the outer ends so a multi-hour entry reads as one bar.
    const r = Radius.circular(8);
    final radius = BorderRadius.only(
      topLeft: seg.isFirstOfEntry ? r : Radius.zero,
      bottomLeft: seg.isFirstOfEntry ? r : Radius.zero,
      topRight: seg.isLastOfEntry ? r : Radius.zero,
      bottomRight: seg.isLastOfEntry ? r : Radius.zero,
    );

    return [
      Positioned(
        left: left,
        top: seg.lane * _laneHeight,
        width: width,
        // 4 px breathing room between stacked lanes.
        height: _laneHeight - 4,
        child: Dismissible(
          key: ValueKey('seg_${seg.entryId}_${hour}_${seg.lane}'),
          direction:
              swipeEnabled ? DismissDirection.endToStart : DismissDirection.none,
          resizeDuration: null,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.20),
              borderRadius: radius,
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent, size: 18),
          ),
          onDismissed: (_) => onSegmentDelete(seg.entryId),
          child: ClipRRect(
            // GlassCard only takes a uniform double radius, so the per-corner
            // shape has to come from the clip.
            borderRadius: radius,
            // GlassCard's own detector is opaque and innermost, so the tap has
            // to be registered there — an outer GestureDetector never sees it.
            child: GlassCard(
              onTap: () => onSegmentTap(seg.entryId),
              // Without an explicit size the card shrinks to its label, so the
              // bar would render as a chip and only the text would be tappable.
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
              opacity: 0.13,
              blurSigma: 6,
              fillColor: color.withValues(alpha: 0.22),
              borderColor: color.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: seg.isFirstOfEntry
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (label.isNotEmpty)
                          Flexible(
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ];
  }
}
