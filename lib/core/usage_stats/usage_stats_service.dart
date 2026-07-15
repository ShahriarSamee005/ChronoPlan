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
  ///  • BACKGROUND (2) event when NOTHING is open → the app must have been in
  ///    the foreground when [windowStart] arrived; count from windowStart.
  ///    Only applied once per package per window (a repeat is a stray/
  ///    duplicate event, not a second implicit session).
  ///  • BACKGROUND (2) event for a package that ISN'T the currently-open one →
  ///    stray/duplicate event; ignored rather than risk a bogus session.
  ///  • DEVICE_SHUTDOWN (26): closes whatever is open; time after shutdown is lost.
  ///  • Session still open after the last event: clamp to min(now, windowEnd),
  ///    flagged as open-ended (no closing event was ever seen).
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
    String? openPkg;
    DateTime? openAt;
    final assumedOpenAtStart = <String>{};

    void closeOpen(DateTime at, {bool openEnded = false}) {
      if (openPkg != null && openAt != null) {
        _addSession(
          sessions, openPkg!, openAt!, at, windowStart, windowEnd,
          openEnded: openEnded,
        );
      }
      openPkg = null;
      openAt = null;
    }

    for (final e in events) {
      // Screen-off and shutdown events have no meaningful packageName — they
      // are global signals that whatever app was foreground has now stopped.
      if (e.type == _kDeviceShutdown ||
          e.type == _kScreenNonInteractive ||
          e.type == _kKeyguardShown) {
        closeOpen(e.timestamp);
        continue;
      }

      if (e.type == 1) {
        // FOREGROUND: only one app can hold this slot, so whatever was open
        // — same package (dropped BACKGROUND) or a different one (app
        // switch) — is done as of right now.
        closeOpen(e.timestamp);
        openPkg = e.packageName;
        openAt = e.timestamp;
      } else if (e.type == 2) {
        if (openPkg == e.packageName) {
          closeOpen(e.timestamp);
        } else if (openPkg == null &&
            assumedOpenAtStart.add(e.packageName)) {
          // No FOREGROUND seen for anyone yet, and we haven't already
          // assumed this package was open-since-start once already.
          _addSession(
            sessions, e.packageName, windowStart, e.timestamp,
            windowStart, windowEnd,
          );
        }
        // else: BACKGROUND for a package that isn't the tracked one —
        // stray/duplicate event; ignore rather than risk a bogus session.
      }
    }

    // Session still open after all events: clamp to min(now, windowEnd).
    if (openPkg != null) {
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
    Map<String, _AppInfo> appInfo,
  ) {
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

    final hourly = await getHourlyUsage(day);

    return UsageDebugSnapshot(
      hourStart: hourStart,
      hourEnd: hourEnd,
      rawEvents: rawEvents,
      sessions: hourSessions,
      stages: stages,
      finalEntries: hourly[hour] ?? const [],
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

  const UsageDebugSnapshot({
    required this.hourStart,
    required this.hourEnd,
    required this.rawEvents,
    required this.sessions,
    required this.stages,
    required this.finalEntries,
  });
}

/// Minimum foreground minutes for an app to be considered real usage.
/// Enforced once in [UsageStatsService._sliceByHour] so the 2a suggestion
/// card and 2b carve proposals — which both read [UsageStatsService.getHourlyUsage] —
/// automatically agree.
const int _minDurationMinutes = 10;

/// Screen turned off — Android does NOT reliably emit MOVE_TO_BACKGROUND for
/// the foreground app when the display goes dark, so this event is the
/// primary mechanism for closing sleep-time sessions.
const int _kScreenNonInteractive = 16;

/// Lock screen appeared — same effect as screen-off for session accounting.
const int _kKeyguardShown = 17;

/// Device shutdown/reboot.  Value 26 confirmed against Android SDK stubs.
/// The previous Kotlin code hardcoded 22 (ROLLOVER_FOREGROUND_SERVICE —
/// a completely different event), so shutdowns were silently ignored before.
const int _kDeviceShutdown = 26;

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
