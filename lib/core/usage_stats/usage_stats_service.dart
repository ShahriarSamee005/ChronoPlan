import 'dart:io';

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

      return totals.entries
          .map((e) => AppUsageEntry(
                packageName: e.key,
                appLabel: _labelFromPackage(e.key),
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

      return _sliceByHour(sessions, dayStart, maxHour);
    } catch (_) {
      return {};
    }
  }

  // ── Channel call ───────────────────────────────────────────────────────────

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

  // ── Session reconstruction ─────────────────────────────────────────────────

  /// Reconstructs foreground sessions from raw FOREGROUND/BACKGROUND events.
  ///
  /// Rules (all in service of "under-count rather than over-count"):
  ///
  ///  • FOREGROUND (1) event → opens a session at event.timestamp.
  ///  • BACKGROUND (2) event with open session → closes it.
  ///  • BACKGROUND (2) event WITHOUT preceding FOREGROUND in the window →
  ///    the app was in the foreground when [windowStart] arrived; count from
  ///    windowStart.  This handles sessions that started before our query.
  ///  • Two consecutive FOREGROUND events (dropped BACKGROUND): close the
  ///    first session at the second FOREGROUND's timestamp (drop phantom time).
  ///  • DEVICE_SHUTDOWN (22): close any open session; app can't survive reboot.
  ///  • Session still open after last event: clamp to min(now, windowEnd).
  ///  • Sessions with zero or negative duration after clamping are discarded.
  List<_Session> _reconstructSessions(
    List<_RawEvent> events,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    // Group by package; events arrive chronologically from the OS.
    final byPackage = <String, List<_RawEvent>>{};
    for (final e in events) {
      byPackage.putIfAbsent(e.packageName, () => []).add(e);
    }

    final sessions = <_Session>[];

    for (final entry in byPackage.entries) {
      final pkg = entry.key;
      final pkgEvents = entry.value;
      DateTime? openAt; // non-null when a foreground session is in progress

      for (final e in pkgEvents) {
        if (e.type == 22) {
          // DEVICE_SHUTDOWN: close open session; time after shutdown is lost.
          if (openAt != null) {
            _addSession(sessions, pkg, openAt, e.timestamp, windowStart);
            openAt = null;
          }
          continue;
        }

        if (e.type == 1) {
          // FOREGROUND event.
          if (openAt != null) {
            // Duplicate FOREGROUND (dropped BACKGROUND): close the previous
            // session at this event's timestamp to avoid double-counting.
            _addSession(sessions, pkg, openAt, e.timestamp, windowStart);
          }
          openAt = e.timestamp;
        } else if (e.type == 2) {
          // BACKGROUND event.
          if (openAt != null) {
            _addSession(sessions, pkg, openAt, e.timestamp, windowStart);
            openAt = null;
          } else {
            // No preceding FOREGROUND seen → session was open at windowStart.
            _addSession(sessions, pkg, windowStart, e.timestamp, windowStart);
          }
        }
      }

      // Session still open after all events for this package.
      if (openAt != null) {
        final capEnd = windowEnd.isAfter(DateTime.now())
            ? DateTime.now()
            : windowEnd;
        _addSession(sessions, pkg, openAt, capEnd, windowStart);
      }
    }

    return sessions;
  }

  void _addSession(
    List<_Session> sessions,
    String pkg,
    DateTime rawStart,
    DateTime end,
    DateTime windowStart,
  ) {
    final start =
        rawStart.isBefore(windowStart) ? windowStart : rawStart;
    if (end.isAfter(start)) {
      sessions.add(_Session(pkg, start, end));
    }
  }

  // ── Per-hour slicing ───────────────────────────────────────────────────────

  /// Clips sessions to each elapsed hour bucket and groups by package.
  Map<int, List<AppUsageEntry>> _sliceByHour(
    List<_Session> sessions,
    DateTime dayStart,
    int maxHour, // exclusive: 0..maxHour-1 hours are reported
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

    return result.map(
      (h, pkgMins) => MapEntry(
        h,
        pkgMins.entries
            .map((e) => AppUsageEntry(
                  packageName: e.key,
                  appLabel: _labelFromPackage(e.key),
                  durationMinutes: e.value,
                ))
            .toList()
          ..sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes)),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Derives a human-readable label from a package name by taking the last
  /// dot-separated segment (e.g. "com.google.android.youtube" → "youtube").
  /// Full Play Store display names require a PackageManager lookup in Kotlin —
  /// deferred to a future enhancement.
  static String _labelFromPackage(String packageName) =>
      packageName.split('.').last;
}

// ── Internal types ────────────────────────────────────────────────────────────

class _RawEvent {
  final String packageName;
  final int type; // 1 = foreground, 2 = background, 22 = shutdown
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

  const _Session(this.packageName, this.start, this.end);

  /// Returns how many whole minutes of this session fall inside [wStart, wEnd).
  int minutesOverlapping(DateTime wStart, DateTime wEnd) {
    final s = start.isBefore(wStart) ? wStart : start;
    final e = end.isAfter(wEnd) ? wEnd : end;
    final ms = e.difference(s).inMilliseconds;
    return ms > 0 ? ms ~/ 60000 : 0;
  }
}
