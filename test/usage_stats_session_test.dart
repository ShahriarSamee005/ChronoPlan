import 'package:chronoplan/core/usage_stats/usage_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Event type ints, matching MainActivity.kt's queryUsageEvents filter.
const _kForeground = 1; // ACTIVITY_RESUMED / MOVE_TO_FOREGROUND
const _kBackground = 2; // ACTIVITY_PAUSED / MOVE_TO_BACKGROUND
const _kShutdown = 26; // DEVICE_SHUTDOWN (the real value; NOT 22)

DebugRawEvent _e(String pkg, int type, DateTime ts) =>
    DebugRawEvent(packageName: pkg, type: type, typeName: '$type', timestamp: ts);

void main() {
  final svc = UsageStatsService();
  // A fixed date safely in the past (never "today"), so the open-session
  // clamp (`min(now, windowEnd)`) deterministically resolves to windowEnd.
  final windowStart = DateTime(2020, 6, 15, 10, 0);
  final windowEnd = DateTime(2020, 6, 15, 11, 0);

  test('Bug B repro: a dropped BACKGROUND for one app is closed by the next '
      'app\'s FOREGROUND, not left open for the whole hour', () {
    // Digital Wellbeing gets resumed briefly, but its own BACKGROUND event
    // never arrives (a real, documented queryEvents quirk). The user then
    // actually switches to YouTube and uses it until the hour is nearly up.
    final events = [
      _e('com.google.android.apps.wellbeing', _kForeground,
          windowStart), // 10:00
      _e('com.google.android.youtube', _kForeground,
          windowStart.add(const Duration(minutes: 5))), // 10:05
      _e('com.google.android.youtube', _kBackground,
          windowStart.add(const Duration(minutes: 47))), // 10:47
    ];

    final sessions =
        svc.reconstructSessionsForTest(events, windowStart, windowEnd);

    expect(sessions.length, 2);

    final wellbeing = sessions
        .firstWhere((s) => s.packageName == 'com.google.android.apps.wellbeing');
    // Must be closed by YouTube's resume at 10:05 — 5 minutes, NOT 60.
    expect(wellbeing.start, windowStart);
    expect(wellbeing.end, windowStart.add(const Duration(minutes: 5)));
    expect(wellbeing.durationMinutes, 5);
    expect(wellbeing.openEnded, isFalse,
        reason: 'closed by the next FOREGROUND event, not left dangling');

    final youtube =
        sessions.firstWhere((s) => s.packageName == 'com.google.android.youtube');
    expect(youtube.start, windowStart.add(const Duration(minutes: 5)));
    expect(youtube.end, windowStart.add(const Duration(minutes: 47)));
    expect(youtube.durationMinutes, 42);
  });

  test('duplicate FOREGROUND for the same package (dropped BACKGROUND) closes '
      'and reopens rather than double-counting', () {
    final events = [
      _e('com.a', _kForeground, windowStart),
      _e('com.a', _kForeground, windowStart.add(const Duration(minutes: 10))),
      _e('com.a', _kBackground, windowStart.add(const Duration(minutes: 15))),
    ];

    final sessions =
        svc.reconstructSessionsForTest(events, windowStart, windowEnd);

    expect(sessions.length, 2);
    expect(sessions[0].durationMinutes, 10);
    expect(sessions[1].durationMinutes, 5);
    final total = sessions.fold<int>(0, (s, e) => s + e.durationMinutes);
    expect(total, 15, reason: 'no time double-counted across the phantom gap');
  });

  test('DEVICE_SHUTDOWN closes whatever is open, regardless of package', () {
    final events = [
      _e('com.a', _kForeground, windowStart),
      _e('com.a', _kShutdown, windowStart.add(const Duration(minutes: 20))),
    ];

    final sessions =
        svc.reconstructSessionsForTest(events, windowStart, windowEnd);

    expect(sessions.length, 1);
    expect(sessions.single.durationMinutes, 20);
    expect(sessions.single.openEnded, isFalse);
  });

  test('a session still open at window end clamps to windowEnd and is '
      'flagged openEnded', () {
    final events = [
      _e('com.a', _kForeground, windowStart.add(const Duration(minutes: 50))),
    ];

    final sessions =
        svc.reconstructSessionsForTest(events, windowStart, windowEnd);

    expect(sessions.length, 1);
    expect(sessions.single.end, windowEnd);
    expect(sessions.single.durationMinutes, 10);
    expect(sessions.single.openEnded, isTrue);
  });

  test('a BACKGROUND with no prior FOREGROUND is assumed open since '
      'windowStart, but only once per package', () {
    final events = [
      _e('com.a', _kBackground, windowStart.add(const Duration(minutes: 5))),
      // Stray duplicate BACKGROUND for the same package — must NOT create a
      // second bogus "since windowStart" session.
      _e('com.a', _kBackground, windowStart.add(const Duration(minutes: 8))),
    ];

    final sessions =
        svc.reconstructSessionsForTest(events, windowStart, windowEnd);

    expect(sessions.length, 1);
    expect(sessions.single.start, windowStart);
    expect(sessions.single.durationMinutes, 5);
  });

  test('a computed session can never exceed the query window — malformed '
      'input is clamped and flagged rather than over-reported', () {
    final events = [
      // Simulates a malformed/out-of-window timestamp arriving before start.
      _e('com.a', _kForeground, windowStart.subtract(const Duration(minutes: 10))),
      _e('com.a', _kBackground, windowStart.add(const Duration(minutes: 5))),
    ];

    final sessions =
        svc.reconstructSessionsForTest(events, windowStart, windowEnd);

    expect(sessions.length, 1);
    expect(sessions.single.start, windowStart);
    expect(sessions.single.end, windowStart.add(const Duration(minutes: 5)));
    expect(sessions.single.clamped, isTrue);
    expect(sessions.single.durationMinutes,
        lessThanOrEqualTo(windowEnd.difference(windowStart).inMinutes));
  });
}
