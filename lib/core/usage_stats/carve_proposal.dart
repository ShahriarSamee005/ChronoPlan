import '../database/app_database.dart';

/// A pending proposal to carve [durationMinutes] of detected [appLabel] usage
/// out of [loggedEntry] for the given [hour] bucket.
///
/// The proposal is computed by [carveProposalsProvider] and rendered inline
/// in the Day View row for that hour.  Nothing is written to the DB until the
/// user taps Confirm.
class CarveProposal {
  final int hour;
  final LogEntry loggedEntry;
  final String packageName;
  final String appLabel;
  // Already capped to the logged entry's remaining duration at provider time.
  final int durationMinutes;

  const CarveProposal({
    required this.hour,
    required this.loggedEntry,
    required this.packageName,
    required this.appLabel,
    required this.durationMinutes,
  });
}
