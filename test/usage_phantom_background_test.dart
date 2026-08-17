// ─────────────────────────────────────────────────────────────────────────
// PHASE A / STEP 1 — FAILING regression tests for the Usage over-counting bug.
//
// These encode the TARGET Phase-A behavior and are EXPECTED TO FAIL against the
// current (broken) reconstruction. They will pass only once the Phase-A fix
// lands. Do NOT "make them pass" by touching reconstruction — that is the next
// gate.
//
// The confirmed bug (usage_stats_service.dart ~L238): a lone unmatched
// BACKGROUND(2) is back-dated to `windowStart` (midnight) whenever
// `openPkg == null` — but openPkg resets to null after EVERY close
// (screen-off / keyguard / shutdown / matched-bg), so stray mid-day
// backgrounds get credited up to ~20h.
//
// Target Phase-A behavior asserted here (NOT implemented yet):
//  • Head case: a lone unmatched BG is back-dated to windowStart ONLY if it is
//    the first session-affecting event of the day (no prior FG or close), AND
//    the gap is <= 90 min; otherwise dropped.
//  • Otherwise a screen-on watermark decides: screen ON leading in
//    (last boundary was SCREEN_INTERACTIVE(15)/KEYGUARD_HIDDEN(18)) →
//    credit [thatScreenOnTime, BG]; screen OFF
//    (SCREEN_NON_INTERACTIVE(16)/KEYGUARD_SHOWN(17)/DEVICE_SHUTDOWN(26)) →
//    credit nothing.
//  • Bucket invariants: no (hour, pkg) > 60 min; no hour total across pkgs > 60.
//
// Synthetic streams intentionally include type 15/18 events. Current Kotlin
// doesn't emit them and current Dart ignores them — that is exactly why the
// watermark tests fail now.
// ─────────────────────────────────────────────────────────────────────────

import 'package:chronoplan/core/usage_stats/usage_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Event-type ints.
const _kForeground = 1; // ACTIVITY_RESUMED / MOVE_TO_FOREGROUND
const _kBackground = 2; // ACTIVITY_PAUSED  / MOVE_TO_BACKGROUND
const _kScreenOn = 15; // SCREEN_INTERACTIVE   (current Dart IGNORES this)
const _kScreenOff = 16; // SCREEN_NON_INTERACTIVE
const _kShutdown = 26; // DEVICE_SHUTDOWN      (Phase B: closes, never resumes)
// Types 17 (KEYGUARD_SHOWN) and 18 (KEYGUARD_HIDDEN) are recognised by
// _typeName below but not needed by these particular streams; screen-on/off
// (15/16) drive the watermark cases and the Phase B suspend/resume cases.

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

  DateTime at(int h, int m) => DateTime(2020, 6, 15, h, m);
  DebugRawEvent e(String pkg, int type, DateTime ts) =>
      DebugRawEvent(packageName: pkg, type: type, typeName: _typeName(type), timestamp: ts);

  List<DebugSession> run(List<DebugRawEvent> events) =>
      svc.reconstructSessionsForTest(events, windowStart, windowEnd);

  // ── In-test bucketing — mirrors _Session.minutesOverlapping exactly (the
  //    already-correct clamp at usage_stats_service.dart:645). Reconstruction
  //    is the code under test; bucketing math is replicated, not exercised
  //    from production, so nothing production changes.
  int overlapMinutes(DateTime s, DateTime en, DateTime wStart, DateTime wEnd) {
    final a = s.isBefore(wStart) ? wStart : s;
    final b = en.isAfter(wEnd) ? wEnd : en;
    final ms = b.difference(a).inMilliseconds;
    return ms > 0 ? ms ~/ 60000 : 0;
  }

  int pkgTotal(List<DebugSession> ss, String pkg) => ss
      .where((s) => s.packageName == pkg)
      .fold(0, (acc, s) => acc + overlapMinutes(s.start, s.end, windowStart, windowEnd));

  int pkgHour(List<DebugSession> ss, String pkg, int hour) {
    final hStart = dayStart.add(Duration(hours: hour));
    final hEnd = hStart.add(const Duration(hours: 1));
    return ss
        .where((s) => s.packageName == pkg)
        .fold(0, (acc, s) => acc + overlapMinutes(s.start, s.end, hStart, hEnd));
  }

  int dayTotalMinutes(List<DebugSession> ss) =>
      ss.fold(0, (acc, s) => acc + overlapMinutes(s.start, s.end, windowStart, windowEnd));

  /// Highest per-(hour, package) bucket across the whole day.
  int maxPkgHourBucket(List<DebugSession> ss) {
    var worst = 0;
    final pkgs = ss.map((s) => s.packageName).toSet();
    for (final p in pkgs) {
      for (var h = 0; h < 24; h++) {
        final v = pkgHour(ss, p, h);
        if (v > worst) worst = v;
      }
    }
    return worst;
  }

  /// Highest single-hour total summed across all packages.
  int maxHourTotalAcrossPkgs(List<DebugSession> ss) {
    var worst = 0;
    for (var h = 0; h < 24; h++) {
      final hStart = dayStart.add(Duration(hours: h));
      final hEnd = hStart.add(const Duration(hours: 1));
      final total =
          ss.fold(0, (acc, s) => acc + overlapMinutes(s.start, s.end, hStart, hEnd));
      if (total > worst) worst = total;
    }
    return worst;
  }

  // ── 1. must FAIL now ──────────────────────────────────────────────────────
  test('phantom_backgrounds_do_not_inflate (must FAIL now)', () {
    // Real foreground use ends when the screen goes off; a stray Instagram
    // BACKGROUND arrives ~20h later with nothing open. It must NOT be
    // back-dated to midnight — the screen was OFF leading into it, so it is
    // dropped.
    final sessions = run([
      e('com.google.android.youtube', _kForeground, at(0, 12)),
      e('android', _kScreenOff, at(0, 18)),
      e('com.instagram.android', _kBackground, at(19, 58)),
    ]);

    // Primary catch: current code credits instagram ~1198 min (~20h).
    expect(pkgTotal(sessions, 'com.instagram.android'), lessThanOrEqualTo(5),
        reason: 'screen was OFF before the stray BG → Phase A drops it');
    // No single reconstructed session for this data may exceed one hour.
    expect(sessions.every((s) => s.durationMinutes <= 60), isTrue,
        reason: 'the phantom [midnight, 19:58] session is ~1198 min');
    // Structural invariants (hold under Phase A).
    expect(dayTotalMinutes(sessions), lessThanOrEqualTo(24 * 60));
    expect(maxPkgHourBucket(sessions), lessThanOrEqualTo(60));
    expect(maxHourTotalAcrossPkgs(sessions), lessThanOrEqualTo(60));
  });

  // ── 2. guardrail — may PASS now ───────────────────────────────────────────
  test('legit_open_across_midnight_credits_from_midnight (guardrail, PASS now)',
      () {
    // Spotify was already playing across midnight; its BACKGROUND is the very
    // first session-affecting event of the day → legit head case, small gap.
    final sessions = run([
      e('com.spotify.music', _kBackground, at(0, 10)),
    ]);

    expect(pkgHour(sessions, 'com.spotify.music', 0), 10);
    expect(pkgTotal(sessions, 'com.spotify.music'), 10);
  });

  // ── 3. must FAIL now ──────────────────────────────────────────────────────
  test('watermark_recovers_post_unlock_usage (must FAIL now)', () {
    // Earlier real activity, long screen-off, then the user unlocks
    // (SCREEN_INTERACTIVE) and uses YouTube; only YouTube's BACKGROUND is seen.
    // Credit must run from the unlock watermark, not from midnight.
    final sessions = run([
      e('com.google.android.gm', _kForeground, at(8, 0)),
      e('com.google.android.gm', _kBackground, at(8, 30)),
      e('android', _kScreenOff, at(20, 7)),
      e('android', _kScreenOn, at(20, 45)), // type 15 — current Dart ignores
      e('com.google.android.youtube', _kBackground, at(21, 30)),
    ]);

    // Phase A: [20:45, 21:30] == 45 min. Current: back-dated to midnight ≈ 1290.
    expect(pkgTotal(sessions, 'com.google.android.youtube'), 45,
        reason: 'screen-on watermark at 20:45, not midnight');
    expect(maxPkgHourBucket(sessions), lessThanOrEqualTo(60));
  });

  // ── 4. must FAIL now ──────────────────────────────────────────────────────
  test('head_case_huge_gap_is_dropped (must FAIL now)', () {
    // First event of the day is a lone BACKGROUND 12h in — implausible as a
    // since-midnight session (> 90 min cap) → dropped.
    final sessions = run([
      e('com.android.chrome', _kBackground, at(12, 0)),
    ]);

    expect(pkgTotal(sessions, 'com.android.chrome'), 0,
        reason: 'head-case back-date capped at 90 min; 12h gap → drop');
  });

  // ── 5. must FAIL now ──────────────────────────────────────────────────────
  test('stray_bg_while_screen_off_is_dropped (must FAIL now)', () {
    // Screen goes off, then a stray Maps BACKGROUND right after. Not the head
    // case (a close preceded it); watermark says screen OFF → drop.
    final sessions = run([
      e('android', _kScreenOn, at(10, 0)), // type 15 — current Dart ignores
      e('android', _kScreenOff, at(10, 30)),
      e('com.google.android.apps.maps', _kBackground, at(10, 35)),
    ]);

    expect(pkgTotal(sessions, 'com.google.android.apps.maps'), 0,
        reason: 'most recent screen boundary was OFF → credit nothing');
  });

  // ── 6. guardrail — must PASS now ──────────────────────────────────────────
  test('cross_hour_session_splits_correctly (guardrail, PASS now)', () {
    // A clean FG→BG session straddling an hour boundary; bucketing is already
    // correct and must stay correct.
    final sessions = run([
      e('com.google.android.gm', _kForeground, at(9, 45)),
      e('com.google.android.gm', _kBackground, at(10, 20)),
    ]);

    expect(pkgHour(sessions, 'com.google.android.gm', 9), 15);
    expect(pkgHour(sessions, 'com.google.android.gm', 10), 20);
    expect(pkgTotal(sessions, 'com.google.android.gm'), 35);
  });

  // ── 7. must FAIL now ──────────────────────────────────────────────────────
  test('anchored_single_wake_yields_full_onscreen_time', () {
    // YouTube open, screen off mid-session, screen back on, then YouTube's BG.
    // A SINGLE-wake stream lands on 35 either way, which is why this one is
    // agnostic to the mask: Phase A closes at the screen-off and rescues the
    // final BG via the watermark at 10:45; Phase B suspends at the screen-off
    // and resumes at 10:45. Same two spans, [10:00,10:30]=30 + [10:45,10:50]=5,
    // with the 10:30–10:45 off-gap excluded. Only an INTERIOR wake (see
    // anchored_multiwake_recovers_interior_wakes) separates the two.
    final sessions = run([
      e('com.google.android.youtube', _kForeground, at(10, 0)),
      e('android', _kScreenOff, at(10, 30)),
      e('android', _kScreenOn, at(10, 45)), // type 15 — current Dart ignores
      e('com.google.android.youtube', _kBackground, at(10, 50)),
    ]);

    expect(pkgTotal(sessions, 'com.google.android.youtube'), 35,
        reason: 'off-gap excluded under both Phase A and the Phase B mask');
    expect(pkgHour(sessions, 'com.google.android.youtube', 10), 35);
    expect(maxPkgHourBucket(sessions), lessThanOrEqualTo(60));
  });

  // ── watermark start floored by lastEnd (no overlap) ───────────────────────
  test('watermark_start_does_not_overlap_prior_session', () {
    // Screen on at 10:00, a real app runs 10:05–10:20, then a lone BG(b) at
    // 10:25. b's watermark start must be max(screenOnSince=10:00,
    // lastEnd=10:20)=10:20 — NOT 10:00, which would overlap a's session.
    final sessions = run([
      e('android', _kScreenOn, at(10, 0)),
      e('com.a', _kForeground, at(10, 5)),
      e('com.a', _kBackground, at(10, 20)),
      e('com.b', _kBackground, at(10, 25)),
    ]);

    expect(pkgTotal(sessions, 'com.a'), 15); // [10:05, 10:20]
    expect(pkgTotal(sessions, 'com.b'), 5); // [10:20, 10:25], not [10:00,...]
    final b = sessions.firstWhere((s) => s.packageName == 'com.b');
    expect(b.start, at(10, 20));
    expect(maxHourTotalAcrossPkgs(sessions), lessThanOrEqualTo(60));
  });

  // ── head-case 90-min boundary ─────────────────────────────────────────────
  test('head_case_boundary_90min', () {
    // Exactly 90 min → credited (≤ cap).
    final at90 = run([e('com.head', _kBackground, at(1, 30))]);
    expect(pkgTotal(at90, 'com.head'), 90);

    // 91 min → dropped (> cap).
    final at91 = run([e('com.head', _kBackground, at(1, 31))]);
    expect(pkgTotal(at91, 'com.head'), 0);
  });

  // ── invariant guard: clamp + record on a forced per-hour overflow ─────────
  test('guard_clamps_and_records_overlap', () {
    // Hand-crafted overlapping sessions in hour 10 — two apps, 40 min each,
    // total 80 > 60. Reconstruction would never emit this; feeding it straight
    // to the bucketer exercises the backstop directly.
    final overlapping = [
      DebugSession(
        packageName: 'com.x',
        start: at(10, 0),
        end: at(10, 40),
        durationMinutes: 40,
        openEnded: false,
        clamped: false,
      ),
      DebugSession(
        packageName: 'com.y',
        start: at(10, 10),
        end: at(10, 50),
        durationMinutes: 40,
        openEnded: false,
        clamped: false,
      ),
    ];

    final out = svc.sliceByHourForTest(overlapping, dayStart, 24);

    // Hour 10's cross-package total is clamped to exactly 60.
    final hour10 = out.buckets[10] ?? const <AppUsageEntry>[];
    final total10 = hour10.fold<int>(0, (a, e) => a + e.durationMinutes);
    expect(total10, 60, reason: 'per-hour total scaled down to 60');

    // A violation was recorded for the hour-total clamp.
    expect(
      out.violations.any((v) => v.hour == 10 && v.pkg == '(hour-total)' && v.rawMinutes == 80 && v.clampedTo == 60),
      isTrue,
      reason: 'the clamp must be surfaced, not silently applied',
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE B / STEP 1 — anchored suspend/resume mask.
  //
  // Target behavior (NOT implemented yet): screen-off (16/17) SUSPENDS an open
  // anchored session — emit the active segment [segmentStart, t] but KEEP the
  // package open — and screen-on (15/18) RESUMES it with a new active segment
  // at t. Matched BG / a different app's FOREGROUND / timeline-end close it
  // for good; DEVICE_SHUTDOWN (26) closes with no possible resume. Net: one
  // contiguous sub-session per screen-on segment, off-gaps excluded.
  //
  // Phase A instead treats every screen-off as a hard close and reopens
  // nothing, so it can only recover the LAST wake — and only indirectly, via
  // the lone-BG screen-on watermark. The unanchored watermark/head/drop path
  // is unaffected by the mask and is guarded by the existing tests above.
  // ═══════════════════════════════════════════════════════════════════════════

  String hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// A package's emitted spans, in order, as 'HH:MM-HH:MM' — segment identity
  /// matters here, not just the total: several of these cases sum to the right
  /// number for the wrong reason.
  List<String> pkgSpans(List<DebugSession> ss, String pkg) => ss
      .where((s) => s.packageName == pkg)
      .map((s) => '${hm(s.start)}-${hm(s.end)}')
      .toList();

  // ── B1. must FAIL now ─────────────────────────────────────────────────────
  test('anchored_multiwake_recovers_interior_wakes (must FAIL now)', () {
    // YouTube stays anchored across TWO screen-off gaps. Every on-screen
    // stretch belongs to it; both off-gaps belong to nobody.
    final sessions = run([
      e('com.google.android.youtube', _kForeground, at(10, 0)),
      e('android', _kScreenOff, at(10, 10)),
      e('android', _kScreenOn, at(10, 15)),
      e('android', _kScreenOff, at(10, 20)),
      e('android', _kScreenOn, at(10, 25)),
      e('com.google.android.youtube', _kBackground, at(10, 30)),
    ]);

    // Phase B: 10 + 5 + 5 == 20.
    // Phase A: the first screen-off closes the session for good, and only the
    // FINAL lone BG is rescued by the watermark at 10:25 → 10 + 5 == 15. The
    // interior 10:15–10:20 wake is credited to nobody.
    expect(pkgSpans(sessions, 'com.google.android.youtube'),
        ['10:00-10:10', '10:15-10:20', '10:25-10:30'],
        reason: 'one contiguous sub-session per screen-on segment');
    expect(pkgTotal(sessions, 'com.google.android.youtube'), 20,
        reason: 'sum of on-screen time; both off-gaps excluded');
    expect(pkgHour(sessions, 'com.google.android.youtube', 10), 20);
    expect(maxPkgHourBucket(sessions), lessThanOrEqualTo(60));
  });

  // ── B2. guardrail — PASSES now, must keep passing ─────────────────────────
  test('different_app_foreground_during_suspend_discards_tail '
      '(guardrail, PASS now)', () {
    // a is suspended by the screen-off, then b takes the foreground without
    // the screen ever coming back on for a. b's FOREGROUND must CLOSE the
    // suspended a — never resume it, and never stretch a to 10:10.
    final sessions = run([
      e('com.a', _kForeground, at(10, 0)),
      e('android', _kScreenOff, at(10, 5)),
      e('com.b', _kForeground, at(10, 10)),
      e('com.b', _kBackground, at(10, 15)),
    ]);

    expect(pkgSpans(sessions, 'com.a'), ['10:00-10:05']);
    expect(pkgSpans(sessions, 'com.b'), ['10:10-10:15']);
    expect(pkgTotal(sessions, 'com.a'), 5);
    expect(pkgTotal(sessions, 'com.b'), 5);
    expect(maxHourTotalAcrossPkgs(sessions), lessThanOrEqualTo(60));
  });

  // ── B3. shutdown closes the anchor; post-boot usage still counts ──────────
  test('shutdown_closes_anchored_session_but_postboot_usage_still_counts', () {
    // Wake, then the device shuts down while a is still the anchored app.
    // Two separate contracts meet here:
    //   1. DEVICE_SHUTDOWN fully CLOSES the anchored session — the mask must
    //      not carry it across the shutdown, and the later screen-on must not
    //      resume it. That is what the straddle invariant below pins down.
    //   2. Whatever the device does after rebooting is ordinary usage. It is
    //      not this session, but it is not nothing either.
    final sessions = run([
      e('com.a', _kForeground, at(10, 0)),
      e('android', _kScreenOff, at(10, 5)),
      e('android', _kScreenOn, at(10, 10)),
      e('android', _kShutdown, at(10, 15)),
      e('android', _kScreenOn, at(10, 20)),
      e('com.a', _kBackground, at(10, 25)),
    ]);

    // [10:00,10:05] active span, suspended by the screen-off.
    // [10:10,10:15] resumed span, closed for good by the shutdown.
    // [10:20,10:25] NOT a leak of the anchored session: after the shutdown
    //   closed it, BG(a)@10:25 arrives as a LONE unmatched BACKGROUND and the
    //   ordinary watermark ladder credits it from screen-on@10:20 — real,
    //   bounded, post-boot foreground time, same as any other post-unlock BG.
    expect(pkgSpans(sessions, 'com.a'),
        ['10:00-10:05', '10:10-10:15', '10:20-10:25']);
    expect(pkgTotal(sessions, 'com.a'), 15);

    // THE guard this test exists for: no single span may STRADDLE the
    // shutdown. A span starting after 10:15 is fine (that's the post-boot
    // one); a span crossing 10:15 would mean the shutdown failed to close the
    // anchored session — the exact regression the mask could introduce.
    final shutdownAt = at(10, 15);
    expect(
      sessions.any((s) =>
          s.start.isBefore(shutdownAt) && s.end.isAfter(shutdownAt)),
      isFalse,
      reason: 'no emitted span may cross DEVICE_SHUTDOWN@10:15',
    );
  });

  // ── B4. guardrail — PASSES now, must keep passing ─────────────────────────
  test('suspended_at_timeline_end_contributes_nothing_more '
      '(guardrail, PASS now)', () {
    // a is suspended near midnight and the day simply runs out — no resume,
    // no closing BG. The end-of-timeline flush must not hand the suspended
    // session the [23:55, windowEnd] off-gap, which is the most likely way for
    // the mask to regress: windowEnd here is a past midnight, so the open-
    // session clamp resolves to it and a wrongly-flushed suspend would show up
    // as a second span worth a full 5 minutes.
    final sessions = run([
      e('com.a', _kForeground, at(23, 50)),
      e('android', _kScreenOff, at(23, 55)),
    ]);

    expect(pkgSpans(sessions, 'com.a'), ['23:50-23:55']);
    expect(pkgTotal(sessions, 'com.a'), 5);
    expect(sessions.any((s) => s.openEnded), isFalse,
        reason: 'a suspended session is not an open-ended one');
  });

  // ── B5. unanchored path unchanged ─────────────────────────────────────────
  // Already covered above and deliberately NOT duplicated here:
  //   • watermark_recovers_post_unlock_usage — unanchored lone BG resolved by
  //     the screen-on watermark.
  //   • phantom_backgrounds_do_not_inflate  — lone BG with the screen off.
  //   • head_case_boundary_90min / head_case_huge_gap_is_dropped — head case.
  //   • watermark_start_does_not_overlap_prior_session — lastEnd floor.
  // The mask only changes what happens while a package is ANCHORED (openPkg
  // non-null), so all five must stay green before and after Phase B.

  // ── clean day → no violations ─────────────────────────────────────────────
  test('clean_day_records_no_violations', () {
    // A normal non-overlapping day reconstructed from events, then sliced.
    final sessions = run([
      e('com.a', _kForeground, at(9, 0)),
      e('com.a', _kBackground, at(9, 30)),
      e('com.b', _kForeground, at(10, 0)),
      e('com.b', _kBackground, at(10, 20)),
    ]);

    final out = svc.sliceByHourForTest(sessions, dayStart, 24);
    expect(out.violations, isEmpty);
  });
}
