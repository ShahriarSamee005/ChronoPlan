import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';

// ── Profile stats provider ────────────────────────────────────────────────────

class _ProfileStats {
  final Duration totalLogged;
  final Map<int, Duration> perCategory; // categoryId → duration
  final DateTime? longestDay;
  final Duration longestDayDuration;

  const _ProfileStats({
    required this.totalLogged,
    required this.perCategory,
    this.longestDay,
    required this.longestDayDuration,
  });
}

final _profileStatsProvider = FutureProvider<_ProfileStats>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final all = await db.logEntriesDao.getAll();

  var total = Duration.zero;
  final perCat = <int, Duration>{};
  final perDay = <String, Duration>{};

  for (final e in all) {
    final dur = e.endTime.difference(e.startTime);
    if (dur.isNegative) continue;
    total += dur;
    if (e.categoryId != null) {
      perCat[e.categoryId!] =
          (perCat[e.categoryId!] ?? Duration.zero) + dur;
    }
    final dayKey = DateFormat('yyyy-MM-dd').format(e.startTime);
    perDay[dayKey] = (perDay[dayKey] ?? Duration.zero) + dur;
  }

  DateTime? longestDay;
  Duration longestDur = Duration.zero;
  for (final entry in perDay.entries) {
    if (entry.value > longestDur) {
      longestDur = entry.value;
      longestDay = DateTime.parse(entry.key);
    }
  }

  return _ProfileStats(
    totalLogged: total,
    perCategory: perCat,
    longestDay: longestDay,
    longestDayDuration: longestDur,
  );
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_profileStatsProvider);
    final catsAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
            children: [
              // ── Stats ─────────────────────────────────────────────────
              statsAsync.when(
                data: (stats) => _StatsCard(
                  stats: stats,
                  cats: catsAsync.valueOrNull ?? [],
                ),
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              // ── Quick links ───────────────────────────────────────────
              _SectionLabel('ACCOUNT'),
              _LinkTile(
                icon: Icons.category_outlined,
                label: 'Categories',
                onTap: () => context.push('/categories'),
              ),
              _LinkTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => context.push('/settings'),
              ),
              _LinkTile(
                icon: Icons.help_outline_rounded,
                label: 'How ChronoPlan works',
                onTap: () => context.push('/onboarding'),
              ),
              _LinkTile(
                icon: Icons.cloud_outlined,
                label: 'Sync (coming soon)',
                onTap: null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stats card ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final _ProfileStats stats;
  final List<Category> cats;

  const _StatsCard({required this.stats, required this.cats});

  @override
  Widget build(BuildContext context) {
    final totalH = stats.totalLogged.inHours;
    final totalM = stats.totalLogged.inMinutes % 60;

    // Top 3 categories by duration
    final sorted = stats.perCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(3).toList();

    return GlassCard(
      opacity: 0.10,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ALL TIME',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'Hours logged',
                  value:
                      '$totalH h ${totalM > 0 ? '${totalM}m' : ''}',
                ),
              ),
              if (stats.longestDay != null)
                Expanded(
                  child: _StatItem(
                    label: 'Best day',
                    value:
                        '${stats.longestDayDuration.inHours}h logged',
                    subtitle: DateFormat('MMM d').format(stats.longestDay!),
                  ),
                ),
            ],
          ),
          if (top3.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'TOP CATEGORIES',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ...top3.map((e) {
              final cat = cats.where((c) => c.id == e.key).firstOrNull;
              final dur = e.value;
              final pct = stats.totalLogged.inMinutes > 0
                  ? (dur.inMinutes / stats.totalLogged.inMinutes * 100)
                      .round()
                  : 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Color(cat?.colorValue ?? 0xFF607D8B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cat?.name ?? 'Unknown',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ),
                    Text(
                      '${dur.inHours}h  $pct%',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;

  const _StatItem({required this.label, required this.value, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        if (subtitle != null)
          Text(subtitle!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        opacity: 0.08,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: onTap != null ? Colors.white : AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: onTap != null
                  ? AppColors.textMuted
                  : AppColors.textMuted.withValues(alpha: 0.40),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
