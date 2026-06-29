import 'package:drift/drift.dart';

/// Persists per-hour, per-app dismissals so that a carve proposal for a
/// specific app in a specific hour doesn't reappear after the user taps Dismiss.
class DismissedCarves extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Midnight of the day this bucket belongs to
  DateTimeColumn get bucketDate => dateTime()();
  // Clock-hour index (0–23)
  IntColumn get bucketHour => integer()();
  // Android package name of the dismissed app
  TextColumn get packageName => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {bucketDate, bucketHour, packageName}
      ];
}
