import 'package:chronoplan/features/log_entry/log_entry_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1: `LogEntrySheet` is day-aware. These cover the pure seeding helper
/// [resolveInitialTimes] (the initState default logic) and the day-aware
/// future guard. When no day is given, seeds must match the pre-day-aware
/// "last completed hour" default exactly.
void main() {
  group('resolveInitialTimes — no day (today) equivalence', () {
    test('mid-day default seeds last completed hour, 1h window', () {
      // 6:45 PM today → 5:00 PM–6:00 PM, exactly as before day-awareness.
      final now = DateTime(2026, 7, 14, 18, 45);
      final today = DateTime(now.year, now.month, now.day);

      final seed = resolveInitialTimes(day: today, now: now);

      expect(seed.start, DateTime(2026, 7, 14, 17));
      expect(seed.end, DateTime(2026, 7, 14, 18));
    });

    test('midnight edge falls back to 23:00 of the previous day', () {
      final now = DateTime(2026, 7, 14, 0, 20);
      final today = DateTime(now.year, now.month, now.day);

      final seed = resolveInitialTimes(day: today, now: now);

      expect(seed.start, DateTime(2026, 7, 13, 23));
      expect(seed.end, DateTime(2026, 7, 14)); // next-day midnight
    });
  });

  group('resolveInitialTimes — explicit day + initialHour', () {
    test('past date at hour 14 seeds 14:00–15:00 on that date', () {
      final pastDay = DateTime(2026, 6, 30);

      final seed = resolveInitialTimes(day: pastDay, initialHour: 14);

      expect(seed.start, DateTime(2026, 6, 30, 14));
      expect(seed.end, DateTime(2026, 6, 30, 15));
    });

    test('hour 23 rolls the end to next-day midnight', () {
      final pastDay = DateTime(2026, 6, 30);

      final seed = resolveInitialTimes(day: pastDay, initialHour: 23);

      expect(seed.start, DateTime(2026, 6, 30, 23));
      expect(seed.end, DateTime(2026, 7, 1)); // midnight of the next day
    });

    test('a normalized-midnight day is used regardless of the time component',
        () {
      // A caller may hand in any DateTime on the target date; only the date
      // part matters.
      final dayWithTime = DateTime(2026, 6, 30, 9, 37);

      final seed = resolveInitialTimes(day: dayWithTime, initialHour: 8);

      expect(seed.start, DateTime(2026, 6, 30, 8));
      expect(seed.end, DateTime(2026, 6, 30, 9));
    });
  });

  group('save-time future guard (mirrors _save)', () {
    // The guard the sheet applies before insert: block if either endpoint is
    // after real now; past is always allowed.
    bool blocksFuture(DateTime start, DateTime end, DateTime now) =>
        start.isAfter(now) || end.isAfter(now);

    test('a future window (today, a future hour) is blocked', () {
      final now = DateTime(2026, 7, 14, 10, 0); // it is 10:00
      final today = DateTime(now.year, now.month, now.day);
      final seed = resolveInitialTimes(day: today, initialHour: 15); // 15–16

      expect(blocksFuture(seed.start, seed.end, now), isTrue);
    });

    test('a past-day window is allowed', () {
      final now = DateTime(2026, 7, 14, 10, 0);
      final pastDay = DateTime(2026, 6, 30);
      final seed = resolveInitialTimes(day: pastDay, initialHour: 14);

      expect(blocksFuture(seed.start, seed.end, now), isFalse);
    });

    test('an earlier-today window is allowed', () {
      final now = DateTime(2026, 7, 14, 18, 45);
      final today = DateTime(now.year, now.month, now.day);
      final seed = resolveInitialTimes(day: today, now: now); // 17–18

      expect(blocksFuture(seed.start, seed.end, now), isFalse);
    });
  });
}
