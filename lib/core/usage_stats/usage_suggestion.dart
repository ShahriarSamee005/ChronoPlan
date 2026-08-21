/// A single pending suggestion produced by the usage-stats engine.
///
/// One suggestion is produced per empty hour bucket where total foreground
/// app usage meets the minimum threshold (10 min).  The engine operates on
/// TODAY only; extending to recent past days is a later enhancement.
class UsageSuggestion {
  /// Clock-hour index (0–23) this bucket covers.
  final int hour;

  /// Exact start of the hour window (midnight + [hour] hours).
  final DateTime bucketStart;

  /// Exact end of the hour window (bucketStart + 1 h).
  final DateTime bucketEnd;

  /// Human-readable app summary, e.g. "Youtube (35m), Chrome (12m), Gmail (8m)".
  /// Built from the top-3 apps by foreground duration in the bucket.
  /// Note: app labels are the last package-name segment, not Play Store display
  /// names — full display-name resolution is a later enhancement.
  final String description;

  /// Total detected foreground minutes in this bucket, across all kept apps.
  ///
  /// Guaranteed <= 60: `UsageStatsService._enforceHourGuards` scales each
  /// hour's cross-package total down to 60 before the per-app entries are
  /// built, and the later filters only remove minutes. Confirm writes a block
  /// of exactly this length so the rest of the hour stays free for a hand log.
  final int totalMinutes;

  const UsageSuggestion({
    required this.hour,
    required this.bucketStart,
    required this.bucketEnd,
    required this.description,
    required this.totalMinutes,
  });
}
