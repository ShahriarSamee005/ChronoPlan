// ─────────────────────────────────────────────────────────────────────────
// PHASE 1 — session merging + minute rounding.
//
// Two linked defects destroyed usage data before any threshold was applied:
//
//  Bug 1 — sessions are shredded. Android emits FOREGROUND/BACKGROUND per
//    ACTIVITY, not per app, so normal in-app navigation (Reels, story viewers,
//    comment sheets, in-app browsers) splits one continuous stretch of use into
//    dozens of fragments. `_reconstructSessions` closed the running session on
//    every FOREGROUND — even for the SAME package — and nothing merged them
//    back afterwards.
//
//  Bug 2 — each fragment was floored to whole minutes BEFORE summing.
//    `_Session.minutesOverlapping` returned `ms ~/ 60000` per session, so the
//    hour total was a sum of floors rather than the floor of a sum. A
//    50-second fragment credited 0; twelve 10-second fragments are 120 real
//    seconds and credited 0 minutes.
//
// Tests A and B pin the two fixes. Tests C and D are the guards that merging
// has NOT gone too far — a real app switch and a genuine screen-off gap must
// still split. Test E is the "5 + break + 5 in one hour" case from the
// diagnostic.
// ─────────────────────────────────────────────────────────────────────────

import 'package:chronoplan/core/usage_stats/usage_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Event-type ints, matching MainActivity.kt's queryUsageEvents filter.
const _kForeground = 1; // ACTIVITY_RESUMED / MOVE_TO_FOREGROUND
const _kBackground = 2; // ACTIVITY_PAUSED  / MOVE_TO_BACKGROUND
const _kScreenOn = 15; // SCREEN_INTERACTIVE
const _kScreenOff = 16; // SCREEN_NON_INTERACTIVE

String _typeName(int t) => switch (t) {
      1 => 'FOREGROUND',
      2 => 'BACKGROUND',
      15 => 'SCREEN_INTERACTIVE',
      16 => 'SCREEN_NON_INTERACTIVE',
      17 => 'KEYGUARD_SHOWN',
      18 => 'KEYGUARD_HIDDEN',
      26 => 'DEVICE_SHUTDOWN',
      _ => 'TYPE_$t',
    };

void main() {
  final svc = UsageStatsService();

  // A fixed day safely in the past so the open-session clamp deterministically
  // resolves to windowEnd. Full-day window, exactly like getHourlyUsage.
  final dayStart = DateTime(2020, 6, 15);
  final windowStart = dayStart;
  final windowEnd = dayStart.add(const Duration(days: 1));

  DateTime at(int h, int m, [int s = 0]) => DateTime(2020, 6, 15, h, m, s);

  DebugRawEvent e(String pkg, int type, DateTime ts) => DebugRawEvent(
      packageName: pkg, type: type, typeName: _typeName(type), timestamp: ts);

  List<DebugSession> run(List<DebugRawEvent> events) =>
      svc.reconstructSessionsForTest(events, windowStart, windowEnd);

  String hms(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}';

  List<String> spans(List<DebugSession> ss, String pkg) => ss
      .where((s) => s.packageName == pkg)
      .map((s) => '${hms(s.start)}-${hms(s.end)}')
      .toList();

  /// Raw per-(hour, package) minutes, before the userFacing / threshold
  /// filters — the bucketing arithmetic on its own.
  int bucketed(List<DebugSession> ss, String pkg, int hour) =>
      svc.bucketMinutesForTest(ss, dayStart, 24)[hour]?[pkg] ?? 0;

  // ── A — sub-minute fragments must not be rounded away ────────────────────
  test('A: twelve 10-second same-package fragments credit 2 minutes, not 0',
      () {
    // Fed straight to the bucketer as already-reconstructed sessions, so this
    // isolates Bug 2: no merging is involved, only the arithmetic. Each
    // fragment is 10s; twelve of them are exactly 120s == 2 minutes.
    final frags = <DebugSession>[
      for (var i = 0; i < 12; i++)
        DebugSession(
          packageName: 'com.frag',
          start: at(10, 0).add(Duration(seconds: i * 10)),
          end: at(10, 0).add(Duration(seconds: (i + 1) * 10)),
          durationMinutes: 0,
          openEnded: false,
          clamped: false,
        ),
    ];

    expect(bucketed(frags, 'com.frag', 10), 2,
        reason: 'sum the milliseconds, then floor ONCE — not floor-then-sum');
  });

  // ── B — one continuous stretch of use is ONE session ─────────────────────
  test('B: an Instagram-style pause/resume storm reconstructs as one session',
      () {
    // The real fragmentation signature: ACTIVITY_PAUSED immediately followed
    // by ACTIVITY_RESUMED for the SAME package, over and over, as the user
    // moves between Reels / story viewer / comment sheet. No other app ever
    // takes the foreground and the screen never goes off.
    const pkg = 'com.instagram.android';
    final events = <DebugRawEvent>[e(pkg, _kForeground, at(10, 0, 0))];
    for (var i = 1; i <= 11; i++) {
      final t = at(10, 0, 0).add(Duration(seconds: i * 10));
      events.add(e(pkg, _kBackground, t));
      events.add(e(pkg, _kForeground, t));
    }
    events.add(e(pkg, _kBackground, at(10, 2, 0)));

    final sessions = run(events);

    expect(sessions.length, 1,
        reason: 'twelve Activity handoffs are one stretch of use');
    expect(spans(sessions, pkg), ['10:00:00-10:02:00']);
    expect(bucketed(sessions, pkg, 10), 2);
  });

  // ── C — guard: a real app switch still splits ────────────────────────────
  test('C: a different app taking the foreground still splits the session',
      () {
    final sessions = run([
      e('com.a', _kForeground, at(10, 0)),
      e('com.b', _kForeground, at(10, 5)),
      e('com.b', _kBackground, at(10, 10)),
    ]);

    expect(sessions.length, 2, reason: 'two different apps, two sessions');
    expect(spans(sessions, 'com.a'), ['10:00:00-10:05:00']);
    expect(spans(sessions, 'com.b'), ['10:05:00-10:10:00']);
    expect(bucketed(sessions, 'com.a', 10), 5);
    expect(bucketed(sessions, 'com.b', 10), 5);
  });

  // ── D — guard: a genuine screen-off gap is not merged away ───────────────
  test('D: a screen-off gap splits the same package and is not credited', () {
    // Same package either side, but the screen was provably off in between.
    // The suspend is a barrier: these are two stretches of use, and the
    // 15 minutes of screen-off time belong to nobody.
    final sessions = run([
      e('com.a', _kForeground, at(10, 0)),
      e('android', _kScreenOff, at(10, 5)),
      e('android', _kScreenOn, at(10, 20)),
      e('com.a', _kBackground, at(10, 25)),
    ]);

    expect(sessions.length, 2, reason: 'a screen-off suspend is a barrier');
    expect(spans(sessions, 'com.a'), ['10:00:00-10:05:00', '10:20:00-10:25:00']);
    expect(bucketed(sessions, 'com.a', 10), 10,
        reason: 'on-screen time only; the 15-minute off-gap is nobody\'s');
  });

  // ── E — 5 + break + 5 in one hour reaches the threshold ──────────────────
  test('E: 5 min + a break + 5 min of one app in one hour credits 10 and '
      'survives the minimum-duration threshold', () {
    final sessions = run([
      e('com.e', _kForeground, at(10, 0)),
      e('com.e', _kBackground, at(10, 5)),
      e('com.e', _kForeground, at(10, 20)),
      e('com.e', _kBackground, at(10, 25)),
    ]);

    expect(sessions.length, 2,
        reason: 'a 15-minute gap is a real break, far past the merge window');
    expect(bucketed(sessions, 'com.e', 10), 10, reason: '5 + 5 summed');

    // And it must survive _minDurationMinutes (10) into the production output.
    final sliced = svc.sliceByHourForTest(sessions, dayStart, 24);
    final hour10 = sliced.buckets[10] ?? const <AppUsageEntry>[];
    expect(hour10.length, 1);
    expect(hour10.single.packageName, 'com.e');
    expect(hour10.single.durationMinutes, 10);
    expect(sliced.violations, isEmpty);
  });

  // ── invariants: merging must not create overlap or overflow ──────────────
  test('merged sessions preserve the structural invariants', () {
    const pkg = 'com.instagram.android';
    // A dense fragment storm spanning an hour boundary, with a real app
    // switch and a screen-off barrier mixed in.
    final events = <DebugRawEvent>[e(pkg, _kForeground, at(10, 40, 0))];
    for (var i = 1; i <= 100; i++) {
      final t = at(10, 40, 0).add(Duration(seconds: i * 20));
      events.add(e(pkg, _kBackground, t));
      events.add(e(pkg, _kForeground, t));
    }
    events
      ..add(e(pkg, _kBackground, at(11, 13, 20)))
      ..add(e('com.other', _kForeground, at(11, 20)))
      ..add(e('com.other', _kBackground, at(11, 30)));

    final sessions = run(events);

    // No negative or zero durations.
    expect(sessions.every((s) => s.end.isAfter(s.start)), isTrue);
    // No session escapes the query window.
    expect(
      sessions.every((s) =>
          !s.start.isBefore(windowStart) && !s.end.isAfter(windowEnd)),
      isTrue,
    );
    // No two sessions overlap.
    final ordered = [...sessions]..sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < ordered.length; i++) {
      expect(ordered[i].start.isBefore(ordered[i - 1].end), isFalse,
          reason: 'sessions must not overlap after merging');
    }

    // No per-(hour, package) bucket exceeds 60, and the guards stay quiet.
    final sliced = svc.sliceByHourForTest(sessions, dayStart, 24);
    for (final entries in sliced.buckets.values) {
      expect(entries.fold<int>(0, (a, x) => a + x.durationMinutes),
          lessThanOrEqualTo(60));
      expect(entries.every((x) => x.durationMinutes <= 60), isTrue);
    }
    expect(sliced.violations, isEmpty,
        reason: 'merging must not manufacture an overflow');

    // The storm is one session per hour-spanning stretch, not 101 fragments.
    expect(spans(sessions, pkg), ['10:40:00-11:13:20']);
    expect(bucketed(sessions, pkg, 10), 20); // 10:40 → 11:00
    expect(bucketed(sessions, pkg, 11), 13); // 11:00 → 11:13:20
  });
}
