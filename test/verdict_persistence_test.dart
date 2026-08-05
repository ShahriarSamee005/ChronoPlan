import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';

// The verdict (thumbs up/down) path was explicitly left untouched in Phase 4
// (daily_intentions stays the home for verdict_positive only). This confirms
// it still round-trips exactly as before: "reopen" = a fresh query for the
// same day, same as the debrief screen does via todayIntentionProvider.
void main() {
  test('thumbs up/down persists across a fresh query ("reopen")', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings();
    final today = DateTime.now();

    await db.intentionsDao.setVerdict(today, true);
    var reopened = await db.intentionsDao.getForDate(today);
    expect(reopened!.verdictPositive, isTrue);

    // Toggle to negative (mirrors the debrief screen's tap-to-toggle logic).
    await db.intentionsDao.setVerdict(today, false);
    reopened = await db.intentionsDao.getForDate(today);
    expect(reopened!.verdictPositive, isFalse);

    // Toggle off entirely (tapping an already-active button clears it).
    await db.intentionsDao.setVerdict(today, null);
    reopened = await db.intentionsDao.getForDate(today);
    expect(reopened!.verdictPositive, isNull);

    await db.close();
  });

  test('setVerdict creates a placeholder row when no intention row exists yet',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.getSettings();
    final today = DateTime.now();

    expect(await db.intentionsDao.getForDate(today), isNull);
    await db.intentionsDao.setVerdict(today, true);

    final row = await db.intentionsDao.getForDate(today);
    expect(row, isNotNull);
    expect(row!.verdictPositive, isTrue);
    expect(row.intention, ''); // placeholder, matches existing behavior

    await db.close();
  });
}
