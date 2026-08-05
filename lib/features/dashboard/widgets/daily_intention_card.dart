import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/intention_tasks_provider.dart';
import '../../tasks/intention_task_sheet.dart';

const _kEmptyPrompt = "What's the one thing that would make today a win?";

class DailyIntentionCard extends ConsumerWidget {
  const DailyIntentionCard({super.key});

  /// flagged task → else #1 task (lowest sortOrder) → else empty-state prompt.
  static String _displayText(List<IntentionTask> tasks) {
    if (tasks.isEmpty) return _kEmptyPrompt;
    final flagged = tasks.where((t) => t.isFlagged).firstOrNull;
    return (flagged ?? tasks.first).label;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final dayKey = DateTime(today.year, today.month, today.day);
    // Same cached, day-keyed roll-forward the task sheet watches (Phase 2) —
    // the dashboard is often the only screen opened after midnight, so it
    // needs to trigger this too, not just the sheet. Riverpod caches the
    // future per day, so this doesn't duplicate the DB write if the sheet
    // has already triggered it this session (or vice versa).
    final rollForwardAsync = ref.watch(rollForwardProvider(dayKey));
    final tasksAsync = ref.watch(dayTasksProvider);

    if (!rollForwardAsync.hasValue) return const SizedBox.shrink();

    return tasksAsync.when(
      data: (tasks) {
        final text = _displayText(tasks);
        final hasTask = tasks.isNotEmpty;
        return GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          opacity: 0.10,
          onTap: () => _openTaskSheet(context),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentForHour(DateTime.now().hour),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE').format(DateTime.now()).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: TextStyle(
                        color: hasTask
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontSize: 14,
                        fontWeight:
                            hasTask ? FontWeight.w500 : FontWeight.w400,
                        fontStyle:
                            hasTask ? FontStyle.normal : FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                hasTask ? Icons.checklist_rounded : Icons.add_rounded,
                color: AppColors.textMuted,
                size: 18,
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _openTaskSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const IntentionTaskSheet(),
    );
  }
}
