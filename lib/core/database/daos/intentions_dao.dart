import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/daily_intentions_table.dart';

part 'intentions_dao.g.dart';

@DriftAccessor(tables: [DailyIntentions])
class IntentionsDao extends DatabaseAccessor<AppDatabase>
    with _$IntentionsDaoMixin {
  IntentionsDao(super.db);

  Stream<DailyIntention?> watchForDate(DateTime date) {
    final day = _dayKey(date);
    return (select(dailyIntentions)..where((i) => i.date.equals(day)))
        .watchSingleOrNull();
  }

  Future<DailyIntention?> getForDate(DateTime date) {
    final day = _dayKey(date);
    return (select(dailyIntentions)..where((i) => i.date.equals(day)))
        .getSingleOrNull();
  }

  Future<void> upsertForDate(DateTime date, String text) async {
    final day = _dayKey(date);
    final existing = await getForDate(date);
    if (existing == null) {
      await into(dailyIntentions).insert(DailyIntentionsCompanion.insert(
        intention: text,
        date: day,
      ));
    } else {
      await (update(dailyIntentions)
            ..where((i) => i.id.equals(existing.id)))
          .write(DailyIntentionsCompanion(intention: Value(text)));
    }
  }

  Future<void> markReflected(int id) =>
      (update(dailyIntentions)..where((i) => i.id.equals(id)))
          .write(const DailyIntentionsCompanion(
              wasReflected: Value(true)));

  Future<void> setVerdict(DateTime date, bool? positive) async {
    final day = _dayKey(date);
    final existing = await getForDate(date);
    if (existing != null) {
      await (update(dailyIntentions)..where((i) => i.id.equals(existing.id)))
          .write(DailyIntentionsCompanion(
              verdictPositive: Value(positive)));
    } else {
      // Create a placeholder intention row so verdict is persisted
      await into(dailyIntentions).insert(DailyIntentionsCompanion.insert(
        intention: '',
        date: day,
        verdictPositive: Value(positive),
      ));
    }
  }

  /// Midnight local time — used as a date-only key.
  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);
}
