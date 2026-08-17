import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ── Public data class (interface unchanged from Phase 2a/2b) ─────────────────

class AppUsageEntry {
  final String packageName;
  final String appLabel;
  final int durationMinutes;

  const AppUsageEntry({
    required this.packageName,
    required this.appLabel,
    required this.durationMinutes,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Provides accurate per-app foreground usage by reading raw
/// UsageStatsManager.queryEvents() events via a Kotlin method channel,
/// then reconstructing foreground sessions entirely in Dart.
///
/// Why events instead of queryUsageStats:
/// queryUsageStats only aggregates into DAILY buckets.  Querying a single
/// one-hour window returns each app's WHOLE-DAY foreground total, not the
/// hour's.  queryEvents gives raw MOVE_TO_FOREGROUND / MOVE_TO_BACKGROUND
/// timestamps, from which accurate per-window durations can be derived.
///
/// IMPORTANT: queryEvents only retains raw events for a limited recent
/// window (typically a few days on stock Android/AOSP).  This is fine for
/// today's hourly view, but any future "reconstruct usage for older days"
/// feature MUST NOT rely on this path — there is no event data to replay.
///
/// Both methods degrade to [] / {} on non-Android and when Usage Access
/// permission has not been granted.
class UsageStatsService {
  static const _channel = MethodChannel('com.example.chronoplan/usage_stats');

  // ── Public API (same signatures as before) ─────────────────────────────────

  /// Returns today's total foreground time per app, sorted by duration desc.
  /// Junk/non-user-facing packages (launcher, our own app, launcher-less
  /// system packages) are excluded; see [_resolveAppInfo].
  Future<List<AppUsageEntry>> getTodayUsage() async {
    if (!Platform.isAndroid) return [];
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final rawEvents = await _queryRawEvents(dayStart, now);
      final sessions = _reconstructSessions(rawEvents, dayStart, now);

      final totals = <String, int>{}; // packageName → totalMinutes
      for (final s in sessions) {
        final mins = s.minutesOverlapping(dayStart, now);
        if (mins > 0) {
          totals[s.packageName] = (totals[s.packageName] ?? 0) + mins;
        }
      }

      final appInfo = await _resolveAppInfo(totals.keys.toSet());

      return totals.entries
          .where((e) => appInfo[e.key]?.userFacing ?? true)
          .map((e) => AppUsageEntry(
                packageName: e.key,
                appLabel: appInfo[e.key]?.label ?? _labelFromPackage(e.key),
                durationMinutes: e.value,
              ))
          .toList()
        ..sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
    } catch (_) {
      return [];
    }
  }

  /// Returns foreground usage bucketed by clock-hour for [day].
  ///
  /// Key   : hour index (0–23)
  /// Value : apps with usage > 0 in that hour, sorted by duration descending.
  ///
  /// A single queryEvents call covers the full day; sessions that span hour
  /// boundaries are split and attributed to each relevant bucket in Dart.
  Future<Map<int, List<AppUsageEntry>>> getHourlyUsage(DateTime day) async {
    if (!Platform.isAndroid) return {};
    try {
      final now = DateTime.now();
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final queryEnd = dayEnd.isAfter(now) ? now : dayEnd;

      if (dayStart.isAfter(now)) return {};

      final rawEvents = await _queryRawEvents(dayStart, queryEnd);
      final sessions = _reconstructSessions(rawEvents, dayStart, queryEnd);

      // How many complete hours to report (only elapsed hours today).
      final isToday = day.year == now.year &&
          day.month == now.month &&
          day.day == now.day;
      final maxHour = isToday ? now.hour : 24;

      final appInfo = await _resolveAppInfo(
        sessions.map((s) => s.packageName).toSet(),
      );

      return _sliceByHour(sessions, dayStart, maxHour, appInfo);
    } catch (_) {
      return {};
    }
  }

  // ── Channel calls ──────────────────────────────────────────────────────────

  /// Fetches raw events from the Kotlin channel for [start, end].
  Future<List<_RawEvent>> _queryRawEvents(
      DateTime start, DateTime end) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'queryUsageEvents',
      {
        'startMs': start.millisecondsSinceEpoch,
        'endMs': end.millisecondsSinceEpoch,
      },
    );
    if (raw == null) return [];
    return raw.map((e) {
      final m = e as Map;
      return _RawEvent(
        packageName: m['p'] as String,
        type: (m['t'] as num).toInt(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (m['ts'] as num).toInt()),
      );
    }).toList();
  }

  /// Resolves display label + "is this real user-facing usage" for each
  /// package in [packages] via the Kotlin PackageManager lookup.
  /// Degrades to an empty map on any error (callers fall back gracefully).
  Future<Map<String, _AppInfo>> _resolveAppInfo(Set<String> packages) async {
    if (packages.isEmpty) return {};
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'resolveAppInfo',
        {'packages': packages.toList()},
      );
      if (raw == null) return {};
      return raw.map((pkg, info) {
        final m = info as Map;
        return MapEntry(
          pkg,
          _AppInfo(
            label: m['label'] as String? ?? pkg,
            userFacing: m['userFacing'] as bool? ?? true,
          ),
        );
      });
    } catch (_) {
      return {};
    }
  }

  // ── Session reconstruction ─────────────────────────────────────────────────

  /// Reconstructs foreground sessions from raw FOREGROUND/BACKGROUND events.
  ///
  /// Android only ever has ONE app in the foreground at a time, so this walks
  /// the events in chronological order as a SINGLE merged stream — never
  /// per-package in isolation — and tracks at most one open session globally.
  /// That single fact is what prevents runaway durations: if an app's own
  /// BACKGROUND event is dropped (a known real-world queryEvents quirk), the
  /// NEXT app's FOREGROUND event still closes it, because opening a new
  /// session always closes whatever was previously open first.
  ///
  /// Rules (all in service of "under-count rather than over-count"):
  ///
  ///  • FOREGROUND (1) event → closes whatever session is currently open
  ///    (same package or not — covers both a dropped BACKGROUND for the same
  ///    app and a normal app switch), then opens a new session for this
  ///    package at event.timestamp.
  ///  • BACKGROUND (2) event for the package that's currently open → closes it.
  ///  • BACKGROUND (2) event for a DIFFERENT open package → stray/duplicate;
  ///    ignored, the real open session is left intact.
  ///  • BACKGROUND (2) event when NOTHING is open (a lone unmatched BG) is
  ///    resolved by the Phase-A priority ladder — NEVER blindly back-dated to
  ///    windowStart, which was the over-counting bug:
  ///      1. Screen provably ON (last screen boundary was SCREEN_INTERACTIVE
  ///         (15) / KEYGUARD_HIDDEN (18)): credit [max(screenOnSince, lastEnd),
  ///         BG]. The `lastEnd` floor stops it overlapping an already-emitted
  ///         session; if the start isn't before the BG, drop.
  ///      2. Else if this is the FIRST session-affecting event of the day (no
  ///         prior FOREGROUND or close — the legit "already open across
  ///         midnight" head case): credit [windowStart, BG], but only if the
  ///         gap is ≤ 90 min; a larger gap is implausible → drop.
  ///      3. Else (screen provably off, or unknown state after a close): drop.
  ///  • SCREEN_NON_INTERACTIVE (16) / KEYGUARD_SHOWN (17): SUSPEND the anchored
  ///    session (Phase B) — emit the active segment [segmentStart, t] but KEEP
  ///    `openPkg`. The app is still the foreground app; it just isn't accruing
  ///    while the screen is off. Marks the screen off.
  ///  • SCREEN_INTERACTIVE (15) / KEYGUARD_HIDDEN (18): raise the screen-on
  ///    watermark (evidence a later lone BG needs), AND resume a suspended
  ///    anchored session by opening a fresh active segment at t. The two
  ///    effects never collide: the watermark is only ever consumed while
  ///    `openPkg == null`, and a resume only happens while it isn't.
  ///  • DEVICE_SHUTDOWN (26): full close, no resume — the device is going away,
  ///    so whatever happens after a reboot is a different session.
  ///  • Net effect of suspend/resume: an anchored session that spans several
  ///    screen wakes emits one contiguous sub-session per on-screen stretch;
  ///    total credited time is the sum of on-screen time and the off-gaps
  ///    belong to nobody.
  ///  • Session still ACTIVE after the last event: clamp to min(now, windowEnd),
  ///    flagged as open-ended (no closing event was ever seen). A session still
  ///    SUSPENDED at the end contributes nothing further — its last segment was
  ///    already emitted at the screen-off.
  ///  • A session's [start, end] is always clamped to [windowStart, windowEnd] —
  ///    it can never exceed the query window. If clamping actually changed
  ///    either edge, the session is flagged so the debug view can surface it.
  ///  • Sessions with zero or negative duration after clamping are discarded.
  List<_Session> _reconstructSessions(
    List<_RawEvent> events,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final sessions = <_Session>[];

    // Phase-B anchored state:
    //  • openPkg      — the anchored foreground package. SURVIVES a screen-off;
    //    cleared only by a matched BG, a different app's FOREGROUND,
    //    DEVICE_SHUTDOWN, or the end of the timeline.
    //  • segmentStart — start of the CURRENT active segment. `null` while
    //    openPkg is non-null means SUSPENDED: anchored but not accruing.
    String? openPkg;
    DateTime? segmentStart;

    // Phase-A watermark/head-case state, walked in event order:
    //  • sawAnyOpenOrClose — true once any FOREGROUND or any close has been
    //    seen; distinguishes the legit head case from a mid-day stray BG.
    //  • screenOn / screenOnSince — the screen-on watermark. 15/18 raise it,
    //    16/17/26 lower it.
    //  • lastEnd — end of the most recently emitted session; floors watermark
    //    credit so it can never overlap an already-counted span.
    var sawAnyOpenOrClose = false;
    var screenOn = false;
    DateTime? screenOnSince;
    var lastEnd = windowStart;

    /// Emits the current active segment (if the session is accruing) and marks
    /// it suspended. Deliberately leaves `openPkg` alone — the app is still the
    /// anchored foreground app.
    void suspendOpen(DateTime at, {bool openEnded = false}) {
      if (openPkg != null && segmentStart != null) {
        _addSession(
          sessions, openPkg!, segmentStart!, at, windowStart, windowEnd,
          openEnded: openEnded,
        );
        if (at.isAfter(lastEnd)) lastEnd = at;
      }
      segmentStart = null;
    }

    /// Emits the active segment (if any) and ends the session for good. A
    /// session that was already suspended emits nothing more — its off-gap
    /// tail belongs to nobody.
    void closeOpen(DateTime at, {bool openEnded = false}) {
      suspendOpen(at, openEnded: openEnded);
      openPkg = null;
    }

    for (final e in events) {
      // Screen-on: raise the watermark (evidence for a later lone BG), and
      // resume a suspended anchored session with a fresh active segment.
      // The two effects are mutually exclusive by construction — the watermark
      // below is only ever read while openPkg == null, and a resume only fires
      // while openPkg != null — so the same span can never be credited twice.
      if (e.type == _kScreenInteractive || e.type == _kKeyguardHidden) {
        screenOn = true;
        screenOnSince = e.timestamp;
        if (openPkg != null && segmentStart == null) {
          segmentStart = e.timestamp;
        }
        continue;
      }

      // Shutdown: the device is going away. Full close — nothing after a
      // reboot belongs to the session that was anchored before it.
      if (e.type == _kDeviceShutdown) {
        closeOpen(e.timestamp);
        screenOn = false;
        sawAnyOpenOrClose = true;
        continue;
      }

      // Screen off / lock: SUSPEND rather than close. The anchored app is
      // still the foreground app — it simply stops accruing until the screen
      // comes back on, so the off-gap is credited to nobody.
      if (e.type == _kScreenNonInteractive || e.type == _kKeyguardShown) {
        suspendOpen(e.timestamp);
        screenOn = false;
        sawAnyOpenOrClose = true;
        continue;
      }

      if (e.type == 1) {
        // FOREGROUND: only one app can hold this slot, so whatever was open
        // — same package (dropped BACKGROUND) or a different one (app
        // switch) — is done as of right now.
        closeOpen(e.timestamp);
        openPkg = e.packageName;
        segmentStart = e.timestamp;
        sawAnyOpenOrClose = true;
      } else if (e.type == 2) {
        if (openPkg == e.packageName) {
          closeOpen(e.timestamp);
          sawAnyOpenOrClose = true;
        } else if (openPkg != null) {
          // BACKGROUND for a package that isn't the tracked one while another
          // app is genuinely open — stray/duplicate; ignore, keep the real
          // session intact. Do NOT back-date.
        } else {
          // Lone unmatched BACKGROUND (nothing open). Resolve by priority.
          if (screenOn && screenOnSince != null) {
            // 1. Screen provably on → credit from the watermark, floored by
            //    lastEnd so it can't overlap an already-emitted session.
            var start = screenOnSince;
            if (start.isBefore(lastEnd)) start = lastEnd;
            if (start.isBefore(e.timestamp)) {
              _addSession(sessions, e.packageName, start, e.timestamp,
                  windowStart, windowEnd);
              if (e.timestamp.isAfter(lastEnd)) lastEnd = e.timestamp;
            }
          } else if (!sawAnyOpenOrClose) {
            // 2. Head case: first session-affecting event of the day, so the
            //    app was plausibly already open across midnight. Cap the
            //    back-date at 90 min; a larger gap is implausible → drop.
            if (e.timestamp.difference(windowStart) <=
                const Duration(minutes: _kHeadCaseMaxBackdate)) {
              _addSession(sessions, e.packageName, windowStart, e.timestamp,
                  windowStart, windowEnd);
              if (e.timestamp.isAfter(lastEnd)) lastEnd = e.timestamp;
            }
          }
          // 3. else: screen provably off or unknown after a close → drop.
          sawAnyOpenOrClose = true;
        }
      }
    }

    // Still ACTIVE after all events: clamp to min(now, windowEnd). Still
    // SUSPENDED: emit nothing — the final segment was already emitted at the
    // screen-off, and the off-gap that followed belongs to nobody.
    if (openPkg != null && segmentStart != null) {
      final capEnd =
          windowEnd.isAfter(DateTime.now()) ? DateTime.now() : windowEnd;
      closeOpen(capEnd, openEnded: true);
    }

    return sessions;
  }

  void _addSession(
    List<_Session> sessions,
    String pkg,
    DateTime rawStart,
    DateTime rawEnd,
    DateTime windowStart,
    DateTime windowEnd, {
    bool openEnded = false,
  }) {
    var start = rawStart;
    var end = rawEnd;
    var clamped = false;

    if (start.isBefore(windowStart)) {
      start = windowStart;
      clamped = true;
    }
    // Defensive: a session should never legitimately extend past the query
    // window — every event we read from is bounded by [windowStart, windowEnd).
    // If it does, that's a data error; clamp it and flag it rather than ever
    // reporting more foreground time than the window itself contains.
    if (end.isAfter(windowEnd)) {
      end = windowEnd;
      clamped = true;
    }

    if (end.isAfter(start)) {
      sessions.add(_Session(
        pkg, start, end,
        openEnded: openEnded,
        clamped: clamped,
      ));
    }
  }

  // ── Per-hour slicing ───────────────────────────────────────────────────────

  /// Clips sessions to each elapsed hour bucket and groups by package.
  ///
  /// This is the SINGLE place the minimum-duration threshold is enforced —
  /// both the 2a suggestion card and the 2b carve proposals consume this
  /// method's output, so neither ever sees a sub-threshold or non-user-facing
  /// app. Callers that need raw/unfiltered per-app minutes for debugging
  /// must read [_Session] data directly rather than going through this path.
  Map<int, List<AppUsageEntry>> _sliceByHour(
    List<_Session> sessions,
    DateTime dayStart,
    int maxHour, // exclusive: 0..maxHour-1 hours are reported
    Map<String, _AppInfo> appInfo, {
    List<UsageGuardViolation>? violations,
  }) {
    final result = <int, Map<String, int>>{}; // hour → pkg → totalMinutes

    for (final s in sessions) {
      for (var h = 0; h < maxHour; h++) {
        final hStart = dayStart.add(Duration(hours: h));
        final hEnd = hStart.add(const Duration(hours: 1));
        final mins = s.minutesOverlapping(hStart, hEnd);
        if (mins > 0) {
          (result[h] ??= {})[s.packageName] =
              ((result[h]?[s.packageName]) ?? 0) + mins;
        }
      }
    }

    // ── Invariant guards (backstop; on correct reconstruction never fire).
    // Clamp always applies so downstream can never exceed physical limits; the
    // [violations] list is the observability layer surfaced in the debug view.
    _enforceHourGuards(result, violations);

    var rawCount = 0, filteredNotUserFacing = 0, filteredBelowThreshold = 0, keptCount = 0;

    final sliced = result.map(
      (h, pkgMins) {
        final entries = <AppUsageEntry>[];
        for (final e in pkgMins.entries) {
          rawCount++;
          final userFacing = appInfo[e.key]?.userFacing ?? true;
          if (!userFacing) {
            filteredNotUserFacing++;
            continue;
          }
          if (e.value < _minDurationMinutes) {
            filteredBelowThreshold++;
            continue;
          }
          keptCount++;
          entries.add(AppUsageEntry(
            packageName: e.key,
            appLabel: appInfo[e.key]?.label ?? _labelFromPackage(e.key),
            durationMinutes: e.value,
          ));
        }
        entries.sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
        return MapEntry(h, entries);
      },
    );

    debugPrint('UsageStatsService: _sliceByHour raw=$rawCount kept=$keptCount '
        'filtered(notUserFacing)=$filteredNotUserFacing '
        'filtered(belowThreshold)=$filteredBelowThreshold');

    return sliced;
  }

  /// Clamps the accumulated hour→pkg→minutes map so no invariant is violated,
  /// appending a [UsageGuardViolation] for each clamp to [violations] (when
  /// provided). Mutates [result] in place.
  ///
  ///  • No single (hour, package) may exceed 60 min → clamp to 60.
  ///  • No hour's total across packages may exceed 60 min → proportionally
  ///    scale that hour's packages down to a total of exactly 60 (largest-
  ///    remainder rounding), after the per-package clamp.
  ///
  /// These should never fire on a correct reconstruction; when they do, the
  /// clamp keeps the numbers physical and the violation makes it visible.
  void _enforceHourGuards(
    Map<int, Map<String, int>> result,
    List<UsageGuardViolation>? violations,
  ) {
    for (final entry in result.entries) {
      final hour = entry.key;
      final pkgMap = entry.value;

      // Guard 1: per-(hour, package) ≤ 60.
      for (final pkg in pkgMap.keys.toList()) {
        final raw = pkgMap[pkg]!;
        if (raw > 60) {
          violations?.add(UsageGuardViolation(
            hour: hour, pkg: pkg, rawMinutes: raw, clampedTo: 60,
          ));
          pkgMap[pkg] = 60;
        }
      }

      // Guard 2: hour total across packages ≤ 60 (after the per-pkg clamp).
      final total = pkgMap.values.fold(0, (a, b) => a + b);
      if (total > 60) {
        violations?.add(UsageGuardViolation(
          hour: hour, pkg: '(hour-total)', rawMinutes: total, clampedTo: 60,
        ));
        // Proportional scale to a total of exactly 60, largest-remainder.
        final pkgs = pkgMap.keys.toList();
        final floors = <String, int>{};
        final remainders = <MapEntry<String, double>>[];
        var used = 0;
        for (final pkg in pkgs) {
          final exact = pkgMap[pkg]! * 60 / total;
          final fl = exact.floor();
          floors[pkg] = fl;
          used += fl;
          remainders.add(MapEntry(pkg, exact - fl));
        }
        remainders.sort((a, b) => b.value.compareTo(a.value));
        for (var i = 0; i < 60 - used && i < remainders.length; i++) {
          floors[remainders[i].key] = floors[remainders[i].key]! + 1;
        }
        pkgMap
          ..clear()
          ..addAll(floors);
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Fallback label when the Kotlin PackageManager lookup fails (e.g. the app
  /// was uninstalled between the usage event and this query): the last
  /// dot-separated segment of the package name (e.g. "...youtube" → "youtube").
  static String _labelFromPackage(String packageName) =>
      packageName.split('.').last;

  // ── TEMPORARY DEBUG SUPPORT ──────────────────────────────────────────────
  // Powers lib/features/debug/usage_debug_screen.dart only. Safe to delete
  // this section (and that screen) together once the pipeline is trusted —
  // nothing in the production 2a/2b path calls into it.

  /// Builds a full inspection snapshot for [day]'s [hour] bucket: the raw,
  /// completely unfiltered events; the reconstructed sessions overlapping
  /// that hour (with their true start/end, which may extend outside the
  /// hour); and the same filtering stages [_sliceByHour] applies, broken out
  /// so it's visible exactly what each stage removes.
  Future<UsageDebugSnapshot> getDebugSnapshot(DateTime day, int hour) async {
    final dayStart = DateTime(day.year, day.month, day.day);
    final hourStart = dayStart.add(Duration(hours: hour));
    final hourEnd = hourStart.add(const Duration(hours: 1));
    final now = DateTime.now();

    // Stage A: every event type, unfiltered, strictly within the selected hour.
    final rawEnd = hourEnd.isAfter(now) ? now : hourEnd;
    final rawEvents = hourStart.isAfter(now)
        ? <DebugRawEvent>[]
        : await _queryRawEventsDebug(hourStart, rawEnd);

    // Stage B: reconstruct using the EXACT inputs getHourlyUsage() uses (the
    // full day up to now), then keep sessions that overlap the selected hour
    // — showing their true span, not clipped to the hour, so a session that
    // bleeds into the next hour is visible as such.
    final dayEnd = dayStart.add(const Duration(days: 1));
    final queryEnd = dayEnd.isAfter(now) ? now : dayEnd;
    final prodEvents = await _queryRawEvents(dayStart, queryEnd);
    final allSessions = _reconstructSessions(prodEvents, dayStart, queryEnd);
    final hourSessions = allSessions
        .where((s) => s.end.isAfter(hourStart) && s.start.isBefore(hourEnd))
        .map((s) => DebugSession(
              packageName: s.packageName,
              start: s.start,
              end: s.end,
              durationMinutes: s.duration.inMinutes,
              openEnded: s.openEnded,
              clamped: s.clamped,
            ))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // Stage C: per-package raw minutes for this hour, then the same
    // userFacing + threshold checks _sliceByHour applies, plus the actual
    // production output for direct comparison.
    final pkgMins = <String, int>{};
    for (final s in allSessions) {
      final mins = s.minutesOverlapping(hourStart, hourEnd);
      if (mins > 0) pkgMins[s.packageName] = (pkgMins[s.packageName] ?? 0) + mins;
    }
    final appInfo = await _resolveAppInfo(pkgMins.keys.toSet());
    final stages = pkgMins.entries
        .map((e) {
          final info = appInfo[e.key];
          return DebugFilterStage(
            packageName: e.key,
            label: info?.label ?? _labelFromPackage(e.key),
            rawMinutes: e.value,
            userFacing: info?.userFacing ?? true,
            meetsThreshold: e.value >= _minDurationMinutes,
          );
        })
        .toList()
      ..sort((a, b) => b.rawMinutes.compareTo(a.rawMinutes));

    // Slice the full day once, capturing any guard violations, so the debug
    // view shows both the final entries and whether the backstop tripped.
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final maxHour = isToday ? now.hour : 24;
    final allAppInfo =
        await _resolveAppInfo(allSessions.map((s) => s.packageName).toSet());
    final guardViolations = <UsageGuardViolation>[];
    final hourly = _sliceByHour(
      allSessions, dayStart, maxHour, allAppInfo,
      violations: guardViolations,
    );

    return UsageDebugSnapshot(
      hourStart: hourStart,
      hourEnd: hourEnd,
      rawEvents: rawEvents,
      sessions: hourSessions,
      stages: stages,
      finalEntries: hourly[hour] ?? const [],
      guardViolations:
          guardViolations.where((v) => v.hour == hour).toList(growable: false),
    );
  }

  Future<List<DebugRawEvent>> _queryRawEventsDebug(
      DateTime start, DateTime end) async {
    if (!Platform.isAndroid) return [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'queryUsageEventsDebug',
        {
          'startMs': start.millisecondsSinceEpoch,
          'endMs': end.millisecondsSinceEpoch,
        },
      );
      if (raw == null) return [];
      return raw.map((e) {
        final m = e as Map;
        return DebugRawEvent(
          packageName: m['p'] as String,
          type: (m['t'] as num).toInt(),
          typeName: m['tn'] as String? ?? 'UNKNOWN',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (m['ts'] as num).toInt()),
        );
      }).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (_) {
      return [];
    }
  }

  /// Test-only entry point into [_reconstructSessions] — it never touches
  /// `Platform.isAndroid` or the method channel, so it's directly testable
  /// without mocking. Takes/returns the same debug DTOs the debug screen
  /// uses. See test/usage_stats_session_test.dart.
  @visibleForTesting
  List<DebugSession> reconstructSessionsForTest(
    List<DebugRawEvent> events,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final rawEvents = events
        .map((e) => _RawEvent(
              packageName: e.packageName,
              type: e.type,
              timestamp: e.timestamp,
            ))
        .toList();
    final sessions = _reconstructSessions(rawEvents, windowStart, windowEnd);
    return sessions
        .map((s) => DebugSession(
              packageName: s.packageName,
              start: s.start,
              end: s.end,
              durationMinutes: s.duration.inMinutes,
              openEnded: s.openEnded,
              clamped: s.clamped,
            ))
        .toList();
  }

  /// Test-only entry point into [_sliceByHour] over synthetic sessions, so the
  /// invariant guards can be exercised directly (feed deliberately overlapping
  /// sessions and observe the clamp + recorded violations). All packages are
  /// treated as user-facing so nothing is dropped by the userFacing filter.
  @visibleForTesting
  ({Map<int, List<AppUsageEntry>> buckets, List<UsageGuardViolation> violations})
      sliceByHourForTest(
    List<DebugSession> sessions,
    DateTime dayStart,
    int maxHour,
  ) {
    final internal = sessions
        .map((s) => _Session(s.packageName, s.start, s.end,
            openEnded: s.openEnded, clamped: s.clamped))
        .toList();
    final appInfo = {
      for (final s in sessions)
        s.packageName: _AppInfo(label: s.packageName, userFacing: true),
    };
    final violations = <UsageGuardViolation>[];
    final buckets = _sliceByHour(internal, dayStart, maxHour, appInfo,
        violations: violations);
    return (buckets: buckets, violations: violations);
  }
}

// ── TEMPORARY DEBUG data classes ─────────────────────────────────────────────
// See UsageStatsService.getDebugSnapshot above.

class DebugRawEvent {
  final String packageName;
  final int type;
  final String typeName;
  final DateTime timestamp;

  const DebugRawEvent({
    required this.packageName,
    required this.type,
    required this.typeName,
    required this.timestamp,
  });
}

class DebugSession {
  final String packageName;
  final DateTime start;
  final DateTime end;
  final int durationMinutes;
  final bool openEnded;
  final bool clamped;

  const DebugSession({
    required this.packageName,
    required this.start,
    required this.end,
    required this.durationMinutes,
    required this.openEnded,
    required this.clamped,
  });
}

class DebugFilterStage {
  final String packageName;
  final String label;
  final int rawMinutes;
  final bool userFacing;
  final bool meetsThreshold;

  const DebugFilterStage({
    required this.packageName,
    required this.label,
    required this.rawMinutes,
    required this.userFacing,
    required this.meetsThreshold,
  });

  bool get includedInFinal => userFacing && meetsThreshold;
}

class UsageDebugSnapshot {
  final DateTime hourStart;
  final DateTime hourEnd;
  final List<DebugRawEvent> rawEvents;
  final List<DebugSession> sessions;
  final List<DebugFilterStage> stages;
  final List<AppUsageEntry> finalEntries;

  /// Invariant-guard clamps that fired for this hour. Empty on a correct
  /// reconstruction; non-empty means the backstop had to clamp inflated
  /// minutes — surfaced in the debug view as a red "GUARD TRIPPED" section.
  final List<UsageGuardViolation> guardViolations;

  const UsageDebugSnapshot({
    required this.hourStart,
    required this.hourEnd,
    required this.rawEvents,
    required this.sessions,
    required this.stages,
    required this.finalEntries,
    this.guardViolations = const [],
  });
}

/// A single invariant-guard clamp recorded by [UsageStatsService._sliceByHour].
/// [pkg] is the offending package, or the sentinel `'(hour-total)'` when the
/// clamp was on an hour's cross-package total rather than one package.
class UsageGuardViolation {
  final int hour;
  final String pkg;
  final int rawMinutes;
  final int clampedTo;

  const UsageGuardViolation({
    required this.hour,
    required this.pkg,
    required this.rawMinutes,
    required this.clampedTo,
  });

  @override
  String toString() =>
      'UsageGuardViolation(hour: $hour, pkg: $pkg, raw: ${rawMinutes}m → '
      '${clampedTo}m)';
}

/// Minimum foreground minutes for an app to be considered real usage.
/// Enforced once in [UsageStatsService._sliceByHour] so the 2a suggestion
/// card and 2b carve proposals — which both read [UsageStatsService.getHourlyUsage] —
/// automatically agree.
const int _minDurationMinutes = 10;

/// Screen turned on / became interactive.  Phase-A screen-on watermark: a lone
/// unmatched BACKGROUND seen while this is the most recent screen boundary is
/// credited from here, not back-dated to midnight.  API 28+; simply absent on
/// 24–27 (the lone BG then falls through to the drop path).
const int _kScreenInteractive = 15;

/// Screen turned off — Android does NOT reliably emit MOVE_TO_BACKGROUND for
/// the foreground app when the display goes dark, so this event is the
/// primary mechanism for closing sleep-time sessions.
const int _kScreenNonInteractive = 16;

/// Lock screen appeared — same effect as screen-off for session accounting.
const int _kKeyguardShown = 17;

/// Keyguard dismissed (unlock).  Same screen-on watermark role as
/// [_kScreenInteractive]; API 28+.
const int _kKeyguardHidden = 18;

/// Device shutdown/reboot.  Value 26 confirmed against Android SDK stubs.
/// The previous Kotlin code hardcoded 22 (ROLLOVER_FOREGROUND_SERVICE —
/// a completely different event), so shutdowns were silently ignored before.
const int _kDeviceShutdown = 26;

/// Maximum minutes a head-case lone BACKGROUND may be back-dated to
/// [windowStart].  A larger gap is implausible as a single since-midnight
/// session and is dropped rather than counted.
const int _kHeadCaseMaxBackdate = 90;

// ── Internal types ────────────────────────────────────────────────────────────

/// Result of a Kotlin PackageManager lookup for one package.
class _AppInfo {
  final String label;
  final bool userFacing;

  const _AppInfo({required this.label, required this.userFacing});
}

class _RawEvent {
  final String packageName;
  final int type; // 1 = foreground, 2 = background, 26 = shutdown
  final DateTime timestamp;

  const _RawEvent({
    required this.packageName,
    required this.type,
    required this.timestamp,
  });
}

class _Session {
  final String packageName;
  final DateTime start;
  final DateTime end;

  /// True when no closing BACKGROUND event was ever seen for this session —
  /// it was still open at the end of the query window (or "now") and got
  /// clamped there. Surfaced in the debug view as "left open".
  final bool openEnded;

  /// True when [start] and/or [end] had to be clipped to the query window
  /// boundary — either the normal "session began before windowStart" case,
  /// or (if it happened on the end side) a data anomaly where a computed
  /// session tried to extend past windowEnd. Surfaced in the debug view.
  final bool clamped;

  const _Session(
    this.packageName,
    this.start,
    this.end, {
    this.openEnded = false,
    this.clamped = false,
  });

  Duration get duration => end.difference(start);

  /// Returns how many whole minutes of this session fall inside [wStart, wEnd).
  int minutesOverlapping(DateTime wStart, DateTime wEnd) {
    final s = start.isBefore(wStart) ? wStart : start;
    final e = end.isAfter(wEnd) ? wEnd : end;
    final ms = e.difference(s).inMilliseconds;
    return ms > 0 ? ms ~/ 60000 : 0;
  }
}
