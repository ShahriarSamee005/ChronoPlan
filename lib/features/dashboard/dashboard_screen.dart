import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../log_entry/log_entry_sheet.dart';
import 'widgets/current_hour_card.dart';
import 'widgets/daily_intention_card.dart';
import 'widgets/daily_pie_chart_card.dart';
import 'widgets/time_gradient_background.dart';
import '../../providers/pending_reconciliation_provider.dart';
import '../../providers/usage_stats_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cold start delivers no `resumed` lifecycle event, so prime _onResume
    // here — but post-frame: it invalidates providers, and ref.invalidate
    // needs the ProviderScope, which isn't reachable until initState returns.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onResume();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
    if (state == AppLifecycleState.paused) _onPause();
  }

  Future<void> _onResume() async {
    ref.read(settingsNotifierProvider.notifier).incrementAppOpenCount();
    // Re-check usage permission and refresh usage data on every resume so
    // permission grants and new usage are reflected without a full restart.
    ref.invalidate(usagePermissionProvider);
    ref.invalidate(todayUsageProvider);
    ref.invalidate(hourlyUsageForTodayProvider);

    final notifService = ref.read(notificationServiceProvider);
    await notifService.cancelInactivityCheck();

    final db = ref.read(appDatabaseProvider);
    final settings = await db.getSettings();

    if (!settings.sleepModeActive) {
      final mode = settings.reminderMode;
      if (mode == 'custom' || mode == 'strict') {
        await notifService.scheduleCustomInterval(
          intervalMinutes: settings.strictIntervalMinutes,
        );
      } else {
        await notifService.scheduleHourly();
      }
      // B10: always (re-)schedule Sunday reflection after cancelAll()
      await notifService.scheduleWeeklyReflection();
    }
  }

  Future<void> _onPause() async {
    final settings = await ref.read(appDatabaseProvider).getSettings();
    if (!settings.sleepModeActive) {
      await ref.read(notificationServiceProvider).scheduleInactivityCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationTapStreamProvider, (_, next) {
      next.whenData((payload) {
        if (!mounted) return;
        if (payload == kNotifPayloadLogEntry) {
          _openLogSheet();
        } else if (payload == kNotifPayloadWeeklyReflection ||
            payload == kNotifPayloadMorningIntention) {
          context.push('/debrief');
        }
      });
    });

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: GestureDetector(
          onTap: () => context.push('/about'),
          child: const Text(
            'ChronoPlan',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 0.3,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: Colors.white),
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              const CurrentHourCard(),
              const SizedBox(height: 12),
              const DailyIntentionCard(),
              const SizedBox(height: 12),
              const DailyPieChartCard(),
              const SizedBox(height: 12),
              _ScreenTimeCard(onTap: () => context.push('/screen-time')),
              const SizedBox(height: 12),
              _DebriefCard(onTap: () => context.push('/debrief')),
            ],
          ),
        ),
      ),
    );
  }

  void _openLogSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LogEntrySheet(),
    );
  }
}

/// Provider that exposes the notification tap stream to the widget tree.
final notificationTapStreamProvider = StreamProvider<String>((ref) {
  return ref.watch(notificationServiceProvider).tapStream;
});

// ── Screen Time entry card ────────────────────────────────────────────────────

class _ScreenTimeCard extends ConsumerWidget {
  final VoidCallback onTap;
  const _ScreenTimeCard({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = AppColors.accentForHour(DateTime.now().hour);
    final usageAsync = ref.watch(todayUsageProvider);
    final totalMinutes =
        usageAsync.valueOrNull?.fold(0, (s, a) => s + a.durationMinutes) ?? 0;
    final subtitle = totalMinutes > 0
        ? _fmtMinutes(totalMinutes)
        : 'Tap to view screen time';

    final granted = ref.watch(usagePermissionProvider).valueOrNull ?? false;
    // Empty-hour suggestions AND logged hours with pending carves — the same
    // number the suggestions card shows in its header.
    final pending = ref.watch(pendingReconciliationCountProvider);
    final showBadge = granted && pending > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.phone_android_rounded, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Screen Time',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (showBadge) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$pending',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white30, size: 20),
          ],
        ),
      ),
    );
  }
}

String _fmtMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m today';
  if (m == 0) return '${h}h today';
  return '${h}h ${m}m today';
}

// ── Debrief entry card ────────────────────────────────────────────────────────

class _DebriefCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DebriefCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accentForHour(DateTime.now().hour)
                    .withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.accentForHour(DateTime.now().hour),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Debrief with AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Review your day with your AI coach',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white30, size: 20),
          ],
        ),
      ),
    );
  }
}
