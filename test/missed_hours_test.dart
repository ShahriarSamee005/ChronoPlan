import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/log_entry/log_entry_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // "Now" is 14:30, so hours 0–13 are elapsed and eligible to be reported.
  final now = DateTime(2026, 7, 14, 14, 30);
  final today = DateTime(2026, 7, 14);

  LogEntry entryAt(
    int hour, {
    required bool isUsageDerived,
    int startMinute = 0,
    int durationMinutes = 60,
    String description = 'Logged',
  }) {
    final start = today.add(Duration(hours: hour, minutes: startMinute));
    return LogEntry(
      id: hour + (isUsageDerived ? 100 : 0),
      description: description,
      categoryId: null,
      startTime: start,
      endTime: start.add(Duration(minutes: durationMinutes)),
      isRealTime: false,
      isAiParsed: false,
      isUsageDerived: isUsageDerived,
      createdAt: start,
    );
  }

  test('an hour with only a screen-time entry is still reported as missed', () {
    final missed = computeMissedHours(
      [entryAt(9, isUsageDerived: true, description: 'YouTube')],
      now: now,
    );

    expect(missed, contains(9),
        reason: 'confirmed screen time is not the user logging their time');
    expect(missed, List.generate(14, (h) => h),
        reason: 'every elapsed hour is still missing');
  });

  test('the same hour is no longer missed once a user entry overlaps it', () {
    final missed = computeMissedHours(
      [
        entryAt(9, isUsageDerived: true, description: 'YouTube'),
        entryAt(9, isUsageDerived: false, description: 'Deep work'),
      ],
      now: now,
    );

    expect(missed, isNot(contains(9)));
    expect(missed, [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13]);
  });

  test('a partial user entry still covers the hour it overlaps', () {
    final missed = computeMissedHours(
      [
        entryAt(9,
            isUsageDerived: false, startMinute: 40, durationMinutes: 10),
      ],
      now: now,
    );

    expect(missed, isNot(contains(9)),
        reason: 'any overlap counts, as before this change');
  });

  test('empty day → every elapsed hour is missed, the current hour is not', () {
    final missed = computeMissedHours([], now: now);

    expect(missed, List.generate(14, (h) => h));
    expect(missed, isNot(contains(14)), reason: 'the in-progress hour');
    expect(missed, isNot(contains(15)), reason: 'future hours');
  });

  test('a fully logged day reports nothing missing', () {
    final entries = [
      for (var h = 0; h < 14; h++) entryAt(h, isUsageDerived: false),
    ];

    expect(computeMissedHours(entries, now: now), isEmpty);
  });

  test('a day of nothing but screen time reports everything missing', () {
    final entries = [
      for (var h = 0; h < 14; h++) entryAt(h, isUsageDerived: true),
    ];

    expect(computeMissedHours(entries, now: now), List.generate(14, (h) => h));
  });
}
