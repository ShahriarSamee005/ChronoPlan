// ─────────────────────────────────────────────────────────────────────────
// Screen Time preinstalled-app allowlist.
//
// Preinstalled time-sinks (Chrome, YouTube, Facebook, …) ship as system apps,
// so ApplicationInfo.FLAG_SYSTEM marks them non-user-facing and the filter in
// UsageStatsService._sliceByHour used to drop them. kScreenTimeAllowlist flips
// only those named packages false -> true; nothing else changes.
//
// These are the FIRST tests to exercise the userFacing filter itself. Before
// the sliceByHourForTest seam grew its `nonUserFacing` parameter, every test
// session was forced user-facing, so the drop path was unreachable. Test 2 is
// the one that would have failed prior to the allowlist.
// ─────────────────────────────────────────────────────────────────────────

import 'package:chronoplan/core/usage_stats/usage_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final svc = UsageStatsService();
  final dayStart = DateTime(2020, 6, 15);

  DateTime at(int h, int m, [int s = 0]) => DateTime(2020, 6, 15, h, m, s);

  // A single foreground session for [pkg] on the fixed test day, [minutes] long
  // starting at 10:00. 15 minutes clears the 10-minute threshold; 5 does not.
  DebugSession session(String pkg, int minutes) => DebugSession(
        packageName: pkg,
        start: at(10, 0),
        end: at(10, minutes),
        durationMinutes: minutes,
        openEnded: false,
        clamped: false,
      );

  // Packages kept in the hour-10 bucket after the userFacing + threshold filter.
  Set<String> keptInHour10(
    List<DebugSession> sessions, {
    Set<String>? nonUserFacing,
  }) {
    final out = svc.sliceByHourForTest(sessions, dayStart, 24,
        nonUserFacing: nonUserFacing);
    return (out.buckets[10] ?? const <AppUsageEntry>[])
        .map((e) => e.packageName)
        .toSet();
  }

  // ── 1 — the list is pinned; an accidental edit is caught here ─────────────
  test('kScreenTimeAllowlist is exactly the eight expected packages', () {
    expect(
      kScreenTimeAllowlist,
      equals({
        'com.android.chrome',
        'com.google.android.youtube',
        'com.facebook.katana',
        'com.facebook.lite',
        'com.facebook.orca',
        'com.instagram.android',
        'com.netflix.mediaclient',
        'com.heytap.browser',
      }),
    );
    expect(kScreenTimeAllowlist.length, 8);
  });

  // ── 2 — an allowlisted system app now counts (load-bearing) ───────────────
  test('an allowlisted system app IS kept even when marked non-user-facing', () {
    final kept = keptInHour10(
      [session('com.android.chrome', 15)],
      nonUserFacing: {'com.android.chrome'},
    );
    expect(kept, contains('com.android.chrome'),
        reason: 'Chrome is on kScreenTimeAllowlist, so the system-app flag is '
            'overridden and it counts toward Screen Time');
  });

  // ── 3 — a non-allowlisted system app still does NOT count ─────────────────
  test('a non-allowlisted system app is still dropped', () {
    final kept = keptInHour10(
      [session('com.example.somesysapp', 15)],
      nonUserFacing: {'com.example.somesysapp'},
    );
    expect(kept, isNot(contains('com.example.somesysapp')),
        reason: 'not on the allowlist → the userFacing filter drops it');
  });

  // ── 4 — a normal user app is unaffected ───────────────────────────────────
  test('an ordinary user app is kept, exactly as before', () {
    final kept = keptInHour10(
      [session('com.some.userapp', 15)],
      nonUserFacing: {}, // nothing marked system
    );
    expect(kept, contains('com.some.userapp'));
  });

  // ── 5 — additivity guard: the allowlist does NOT bypass the threshold ─────
  test('an allowlisted app below the 10-minute threshold is still dropped', () {
    final kept = keptInHour10(
      [session('com.instagram.android', 5)],
      nonUserFacing: {'com.instagram.android'},
    );
    expect(kept, isNot(contains('com.instagram.android')),
        reason: 'the allowlist only affects userFacing; the 10-minute minimum '
            'still applies, so 5 minutes is not enough');
  });
}
