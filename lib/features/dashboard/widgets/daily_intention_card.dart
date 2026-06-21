import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/intentions_provider.dart';

class DailyIntentionCard extends ConsumerWidget {
  const DailyIntentionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intentionAsync = ref.watch(todayIntentionProvider);

    return intentionAsync.when(
      data: (intention) => GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        opacity: 0.10,
        onTap: () => _openDialog(context, ref, intention?.intention),
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
                    intention?.intention ?? 'Set your intention for today…',
                    style: TextStyle(
                      color: intention != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      fontSize: 14,
                      fontWeight: intention != null
                          ? FontWeight.w500
                          : FontWeight.w400,
                      fontStyle: intention != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              intention != null ? Icons.edit_outlined : Icons.add_rounded,
              color: AppColors.textMuted,
              size: 18,
            ),
          ],
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _openDialog(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Today\'s intention',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'What matters most today?',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    if (result.isEmpty && current != null) return; // don't clear accidentally
    if (result.isNotEmpty) {
      await ref
          .read(appDatabaseProvider)
          .intentionsDao
          .upsertForDate(DateTime.now(), result);
    }
  }
}
