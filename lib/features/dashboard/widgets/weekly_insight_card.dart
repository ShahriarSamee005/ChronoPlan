import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/settings_provider.dart';

class WeeklyInsightCard extends ConsumerStatefulWidget {
  const WeeklyInsightCard({super.key});

  @override
  ConsumerState<WeeklyInsightCard> createState() => _WeeklyInsightCardState();
}

class _WeeklyInsightCardState extends ConsumerState<WeeklyInsightCard> {
  String? _insight;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  DateTime get _weekStart {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  Future<void> _load() async {
    if (_isLoading) return;
    final service = ref.read(aiServiceProvider);

    setState(() {
      _isLoading = true;
      _insight = null;
    });

    final db = ref.read(appDatabaseProvider);
    final entries = await db.logEntriesDao.getForWeek(_weekStart);
    final cats = await db.categoriesDao.getAll();

    if (!mounted) return;

    if (entries.isEmpty) {
      setState(() {
        _isLoading = false;
        _insight =
            'Log some entries this week to get your weekly insight.';
      });
      return;
    }

    final weekJson = _formatWeekData(entries, cats);
    final result = await service.weeklyInsight(weekJson);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _insight = result ?? 'Couldn\'t generate insight. Try again.';
      });
    }
  }

  String _formatWeekData(List<LogEntry> entries, List<Category> cats) {
    final byCategory = <String, int>{};
    final byDay = <String, Map<String, int>>{};
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (final e in entries) {
      final catName = cats
              .where((c) => c.id == e.categoryId)
              .firstOrNull
              ?.name ??
          'Uncategorized';
      final mins = e.endTime.difference(e.startTime).inMinutes;
      byCategory[catName] = (byCategory[catName] ?? 0) + mins;
      final dayName = dayNames[e.startTime.weekday - 1];
      byDay[dayName] ??= {};
      byDay[dayName]![catName] = (byDay[dayName]![catName] ?? 0) + mins;
    }

    return jsonEncode({
      'weekStarting': _weekStart.toIso8601String().substring(0, 10),
      'totalEntries': entries.length,
      'totalMinutes': entries.fold(
          0, (s, e) => s + e.endTime.difference(e.startTime).inMinutes),
      'byCategory': byCategory,
      'byDay': byDay,
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(aiServiceProvider); // rebuild when persona changes
    if (Supabase.instance.client.auth.currentSession == null) {
      return const SizedBox.shrink();
    }

    final accent = AppColors.accentForHour(DateTime.now().hour);

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: accent, size: 15),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Weekly Insight',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!_isLoading)
                GestureDetector(
                  onTap: _load,
                  child: const Icon(Icons.refresh_rounded,
                      color: Colors.white38, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(
                    color: Colors.white54, strokeWidth: 2),
              ),
            )
          else if (_insight != null)
            Text(
              _insight!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }
}
