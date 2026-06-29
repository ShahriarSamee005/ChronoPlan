import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/dismissed_suggestions_table.dart';

part 'dismissed_suggestions_dao.g.dart';

@DriftAccessor(tables: [DismissedSuggestions])
class DismissedSuggestionsDao extends DatabaseAccessor<AppDatabase>
    with _$DismissedSuggestionsDaoMixin {
  DismissedSuggestionsDao(super.db);

  /// Watches all dismissed hour-buckets for a given calendar day.
  Stream<List<DismissedSuggestion>> watchForDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return (select(dismissedSuggestions)
          ..where((s) => s.bucketDate.equals(d)))
        .watch();
  }

  /// Records a dismissed bucket idempotently (safe to call multiple times).
  Future<void> dismiss(DateTime date, int hour) async {
    final d = DateTime(date.year, date.month, date.day);
    await into(dismissedSuggestions).insert(
      DismissedSuggestionsCompanion.insert(bucketDate: d, bucketHour: hour),
      mode: InsertMode.insertOrIgnore,
    );
  }
}
