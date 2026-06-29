import 'package:app_usage/app_usage.dart';

// ── Data class ────────────────────────────────────────────────────────────────

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

/// Wraps the app_usage package to provide per-app foreground usage data.
///
/// AppUsage.getAppUsage() already returns [] on non-Android and when the
/// Usage Access permission is absent, so all methods here degrade silently.
///
/// Note: AppUsageInfo.appName is the last segment of the package name
/// (e.g. "youtube" from "com.google.android.youtube"), not the Play Store
/// display name.  A display-name lookup is deferred to Phase 2.
class UsageStatsService {
  /// Returns today's total foreground time per app, sorted by duration
  /// descending.  Queries the window [midnight .. now].
  Future<List<AppUsageEntry>> getTodayUsage() async {
    try {
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final raw = await AppUsage().getAppUsage(dayStart, now);
      return raw
          .where((i) => i.usage.inMinutes > 0)
          .map((i) => AppUsageEntry(
                packageName: i.packageName,
                appLabel: i.appName,
                durationMinutes: i.usage.inMinutes,
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
  /// Each hour is queried as a separate 1-hour window so usage is attributed
  /// to the correct bucket.  Hours after the current time are skipped.
  Future<Map<int, List<AppUsageEntry>>> getHourlyUsage(DateTime day) async {
    final result = <int, List<AppUsageEntry>>{};
    final dayStart = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();

    for (var hour = 0; hour < 24; hour++) {
      final windowStart = dayStart.add(Duration(hours: hour));
      if (windowStart.isAfter(now)) break;
      final windowEnd = windowStart.add(const Duration(hours: 1));
      final clampedEnd = windowEnd.isAfter(now) ? now : windowEnd;

      try {
        final raw = await AppUsage().getAppUsage(windowStart, clampedEnd);
        final entries = raw
            .where((i) => i.usage.inMinutes > 0)
            .map((i) => AppUsageEntry(
                  packageName: i.packageName,
                  appLabel: i.appName,
                  durationMinutes: i.usage.inMinutes,
                ))
            .toList()
          ..sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
        if (entries.isNotEmpty) result[hour] = entries;
      } catch (_) {
        continue;
      }
    }
    return result;
  }
}
