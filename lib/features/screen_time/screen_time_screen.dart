import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/usage_stats_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';
import '../dashboard/widgets/usage_access_card.dart';
import '../dashboard/widgets/usage_suggestions_card.dart';

class ScreenTimeScreen extends ConsumerWidget {
  const ScreenTimeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: GestureDetector(
          // Long-press keeps the debug screen reachable without cluttering
          // normal navigation — deliberately hidden, same pattern as before.
          onLongPress: () => context.push('/debug-usage'),
          child: const Text(
            'Screen Time',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 0.3,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: const [
              UsageAccessCard(),
              SizedBox(height: 12),
              _TodayUsageCard(),
              SizedBox(height: 12),
              UsageSuggestionsCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Today's usage summary ─────────────────────────────────────────────────────

class _TodayUsageCard extends ConsumerWidget {
  const _TodayUsageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = ref.watch(usagePermissionProvider).valueOrNull ?? false;
    if (!granted) return const SizedBox.shrink();

    final usageAsync = ref.watch(todayUsageProvider);

    return usageAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (apps) {
        if (apps.isEmpty) return const SizedBox.shrink();

        final accent = AppColors.accentForHour(DateTime.now().hour);
        final totalMinutes = apps.fold(0, (s, a) => s + a.durationMinutes);

        return GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: accent, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Today\'s Usage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _fmtMinutes(totalMinutes),
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // ── App rows ──────────────────────────────────────────────────
              ...apps.take(8).map((app) => _AppRow(app: app, accent: accent)),
              if (apps.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '+${apps.length - 8} more apps',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AppRow extends StatelessWidget {
  final AppUsageEntry app;
  final Color accent;

  const _AppRow({required this.app, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _capitalize(app.appLabel),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _fmtMinutes(app.durationMinutes),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _fmtMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

