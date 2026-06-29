import 'package:drift/drift.dart';

/// Persists per-hour buckets the user has explicitly dismissed so they don't
/// reappear as usage suggestions.
class DismissedSuggestions extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Midnight of the day this bucket belongs to
  DateTimeColumn get bucketDate => dateTime()();
  // Clock-hour index (0–23)
  IntColumn get bucketHour => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {bucketDate, bucketHour}
      ];
}
