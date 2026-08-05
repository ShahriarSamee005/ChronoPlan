import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/intention_tasks_dao.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/database_provider.dart';
import '../../providers/intention_tasks_provider.dart';

class IntentionTaskSheet extends ConsumerStatefulWidget {
  const IntentionTaskSheet({super.key});

  @override
  ConsumerState<IntentionTaskSheet> createState() =>
      _IntentionTaskSheetState();
}

class _IntentionTaskSheetState extends ConsumerState<IntentionTaskSheet> {
  final _taskCtrl = TextEditingController();

  @override
  void dispose() {
    _taskCtrl.dispose();
    super.dispose();
  }

  Future<void> _addTask(DateTime today) async {
    final text = _taskCtrl.text.trim();
    if (text.isEmpty) return;
    final result =
        await ref.read(appDatabaseProvider).intentionTasksDao.addTask(today, text);
    if (result == AddTaskResult.added) {
      _taskCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dayKey = DateTime(today.year, today.month, today.day);
    final rollForwardAsync = ref.watch(rollForwardProvider(dayKey));
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: GlassCard(
        borderRadius: 28,
        opacity: 0.20,
        blurSigma: 16,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: SingleChildScrollView(
            child: rollForwardAsync.when(
              data: (_) => _buildContent(context, dayKey),
              loading: () => const SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
              error: (e, _) => SizedBox(
                height: 120,
                child: Center(
                  child: Text('$e', style: const TextStyle(color: Colors.white54)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, DateTime today) {
    final tasksAsync = ref.watch(dayTasksProvider);
    final tasks = tasksAsync.valueOrNull ?? [];
    final atCap = tasks.length >= kMaxTasksPerDay;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        const Text(
          "Today's Tasks",
          style: TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 20),

        // ── Add task ─────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _taskCtrl,
                enabled: !atCap,
                decoration: InputDecoration(
                  hintText: atCap ? '10 max — clear a task first' : 'Add a task…',
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: atCap ? null : (_) => _addTask(today),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle_rounded),
              color: atCap ? AppColors.textMuted : AppColors.accentForHour(DateTime.now().hour),
              onPressed: atCap ? null : () => _addTask(today),
            ),
          ],
        ),
        if (atCap)
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text(
              '10 max',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ),
        const SizedBox(height: 16),

        // ── Task list ────────────────────────────────────────────────────
        if (tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No tasks yet — add the first one above.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          )
        else
          ...tasks.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TaskRow(task: t),
              )),
      ],
    );
  }
}

class _TaskRow extends ConsumerWidget {
  final IntentionTask task;

  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dao = ref.read(appDatabaseProvider).intentionTasksDao;

    return Slidable(
      key: ValueKey('task_${task.id}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (_) => dao.setDone(task.id),
            backgroundColor: Colors.greenAccent.shade400,
            foregroundColor: Colors.black,
            icon: Icons.check_rounded,
            label: 'Done',
            borderRadius: BorderRadius.circular(8),
          ),
          SlidableAction(
            onPressed: (_) => dao.removeTask(task.id),
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: 'Remove',
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      ),
      child: GlassCard(
        borderRadius: 8,
        opacity: 0.10,
        blurSigma: 6,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                task.label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(
                task.isFlagged ? Icons.flag_rounded : Icons.flag_outlined,
                size: 18,
              ),
              color: task.isFlagged
                  ? AppColors.accentForHour(DateTime.now().hour)
                  : AppColors.textMuted,
              tooltip: task.isFlagged ? 'Flagged' : 'Flag as priority',
              onPressed: () => dao.setFlag(task.date, task.id),
            ),
          ],
        ),
      ),
    );
  }
}
