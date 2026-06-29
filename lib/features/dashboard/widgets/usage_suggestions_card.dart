import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/usage_stats_provider.dart';
import '../../../providers/usage_suggestions_provider.dart';

/// Dashboard card that surfaces pending screen-time suggestions.
///
/// Visible only when:
///   • Usage Access is granted, AND
///   • At least one hour bucket qualifies as a pending suggestion.
///
/// Each row lets the user pick a category then either Confirm (creates a
/// retroactive log entry) or Dismiss (persists the dismissal so the bucket
/// won't reappear).  Nothing is written to the log without explicit confirmation.
class UsageSuggestionsCard extends ConsumerStatefulWidget {
  const UsageSuggestionsCard({super.key});

  @override
  ConsumerState<UsageSuggestionsCard> createState() =>
      _UsageSuggestionsCardState();
}

class _UsageSuggestionsCardState extends ConsumerState<UsageSuggestionsCard> {
  // hour → currently selected categoryId (null = no category)
  final Map<int, int?> _selectedCategory = {};
  // hours currently being confirmed (spinner shown)
  final Set<int> _confirming = {};

  @override
  Widget build(BuildContext context) {
    final granted = ref.watch(usagePermissionProvider).valueOrNull ?? false;
    if (!granted) return const SizedBox.shrink();

    final suggestionsValue = ref.watch(usageSuggestionsProvider);

    return suggestionsValue.when(
      data: (suggestions) {
        if (suggestions.isEmpty) return const SizedBox.shrink();

        final cats = ref.watch(categoriesProvider).valueOrNull ?? [];
        final screenTimeCat =
            cats.where((c) => c.name == 'Screen Time').firstOrNull;

        // Set default category to Screen Time once categories are available;
        // putIfAbsent preserves any selection the user has already made.
        if (screenTimeCat != null) {
          for (final s in suggestions) {
            _selectedCategory.putIfAbsent(s.hour, () => screenTimeCat.id);
          }
        }

        final accent = AppColors.accentForHour(DateTime.now().hour);

        return GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.phone_android_rounded, color: accent, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Screen Time Suggestions',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${suggestions.length}',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Tap Confirm to log detected screen time',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 10),

              // ── Suggestion rows ──────────────────────────────────────────
              ...suggestions.map((s) => _SuggestionRow(
                    suggestion: s,
                    cats: cats,
                    selectedCatId: _selectedCategory[s.hour],
                    isConfirming: _confirming.contains(s.hour),
                    onCategoryChanged: (catId) =>
                        setState(() => _selectedCategory[s.hour] = catId),
                    onConfirm: () => _confirm(s),
                    onDismiss: () => _dismiss(s),
                  )),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _confirm(UsageSuggestion s) async {
    setState(() => _confirming.add(s.hour));
    final db = ref.read(appDatabaseProvider);
    try {
      // Goes through insertRetroactive so sacred real-time entries are never
      // overwritten and auto-split rules apply.
      final ids = await db.logEntriesDao.insertRetroactive(
        startTime: s.bucketStart,
        endTime: s.bucketEnd,
        categoryId: _selectedCategory[s.hour],
        description: s.description,
      );
      if (mounted && ids.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That window is already fully logged.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Whether ids is empty or not, the bucket is now "handled":
      // todayEntriesProvider stream will update → suggestion auto-disappears
      // if ids is non-empty; if ids is empty, it means a real-time entry
      // already covers it, so the overlap check will also hide it.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _confirming.remove(s.hour));
    }
  }

  Future<void> _dismiss(UsageSuggestion s) async {
    await ref
        .read(appDatabaseProvider)
        .dismissedSuggestionsDao
        .dismiss(DateTime.now(), s.hour);
    // _dismissedTodayProvider stream updates → usageSuggestionsProvider
    // recomputes → this row disappears automatically.
  }
}

// ── Suggestion row ────────────────────────────────────────────────────────────

class _SuggestionRow extends StatelessWidget {
  final UsageSuggestion suggestion;
  final List<Category> cats;
  final int? selectedCatId;
  final bool isConfirming;
  final void Function(int?) onCategoryChanged;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _SuggestionRow({
    required this.suggestion,
    required this.cats,
    required this.selectedCatId,
    required this.isConfirming,
    required this.onCategoryChanged,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('h a');
    final startLabel = fmt.format(suggestion.bucketStart);
    final endLabel = fmt.format(suggestion.bucketEnd);
    final accent = AppColors.accentForHour(suggestion.hour);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Time range + description ──────────────────────────────────
            Text(
              '$startLabel – $endLabel',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              suggestion.description,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // ── Category chips (horizontal scroll) ────────────────────────
            if (cats.isNotEmpty) ...[
              const Text(
                'CATEGORY',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: cats.map((cat) {
                    final sel = selectedCatId == cat.id;
                    final catColor = Color(cat.colorValue);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        avatar: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: catColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        label: Text(cat.name),
                        selected: sel,
                        onSelected: (selected) =>
                            onCategoryChanged(selected ? cat.id : null),
                        selectedColor: catColor.withValues(alpha: 0.22),
                        checkmarkColor: catColor,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.06),
                        side: BorderSide(
                          color: sel
                              ? catColor.withValues(alpha: 0.60)
                              : Colors.white.withValues(alpha: 0.15),
                        ),
                        labelStyle: TextStyle(
                          color: sel ? Colors.white : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.w400,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── Confirm / Dismiss ─────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isConfirming ? null : onDismiss,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white38,
                      side: const BorderSide(color: Colors.white12),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Dismiss',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: isConfirming ? null : onConfirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: isConfirming
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Confirm',
                            style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
