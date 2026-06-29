import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/usage_stats/usage_permission_channel.dart';
import '../core/usage_stats/usage_stats_service.dart';

export '../core/usage_stats/usage_stats_service.dart' show AppUsageEntry;

final usageStatsServiceProvider = Provider<UsageStatsService>((ref) {
  return UsageStatsService();
});

/// Whether the user has granted Usage Access.  Invalidated on every app
/// resume so permission changes made in the system settings screen are
/// reflected without a full restart.
final usagePermissionProvider = FutureProvider<bool>((ref) {
  return UsagePermissionChannel.isGranted();
});

/// Today's per-app foreground usage, sorted by duration descending.
/// Returns empty when permission is absent or the device is not Android.
final todayUsageProvider = FutureProvider<List<AppUsageEntry>>((ref) {
  return ref.watch(usageStatsServiceProvider).getTodayUsage();
});

/// Per-hour breakdown of today's foreground usage, keyed by clock-hour (0–23).
/// Expensive (24 separate OS queries) — only re-runs when invalidated via
/// [ref.invalidate] (on app resume or after permission is granted).
final hourlyUsageForTodayProvider =
    FutureProvider<Map<int, List<AppUsageEntry>>>((ref) {
  return ref.watch(usageStatsServiceProvider).getHourlyUsage(DateTime.now());
});
