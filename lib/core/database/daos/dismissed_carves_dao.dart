import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/dismissed_carves_table.dart';

part 'dismissed_carves_dao.g.dart';

@DriftAccessor(tables: [DismissedCarves])
class DismissedCarvesDao extends DatabaseAccessor<AppDatabase>
    with _$DismissedCarvesDaoMixin {
  DismissedCarvesDao(super.db);

  /// Watches all dismissed carve entries for a given calendar day.
  Stream<List<DismissedCarve>> watchForDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return (select(dismissedCarves)..where((s) => s.bucketDate.equals(d)))
        .watch();
  }

  /// Records a dismissed (date, hour, package) idempotently.
  Future<void> dismiss(DateTime date, int hour, String packageName) async {
    final d = DateTime(date.year, date.month, date.day);
    await into(dismissedCarves).insert(
      DismissedCarvesCompanion.insert(
        bucketDate: d,
        bucketHour: hour,
        packageName: packageName,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }
}
