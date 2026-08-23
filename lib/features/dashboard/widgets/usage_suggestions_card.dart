import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../core/usage_stats/carve_actions.dart';
import '../../../providers/carve_proposals_provider.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/pending_reconciliation_provider.dart';
import '../../../providers/usage_stats_provider.dart';
import '../../../providers/usage_suggestions_provider.dart';

/// Dashboard card that surfaces everything still waiting to be reconciled
/// against detected screen time:
///
///   • EMPTY hours with detected usage → confirm to log them ([_SuggestionRow])
///   • LOGGED hours with app usage the entry doesn't mention → carve proposals,
///     one row per app ([_CarveRow])
///
/// Visible only when Usage Access is granted AND at least one of those exists.
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
  // carve key ("entryId:package") → currently selected categoryId
  final Map<String, int?> _carveCategory = {};
  // carve keys with in-flight confirms
  final Set<String> _carveConfirming = {};

  static String _carveKey(CarveProposal p) =>
      '${p.loggedEntry.id}:${p.packageName}';

  @override
  Widget build(BuildContext context) {
    final granted = ref.watch(usagePermissionProvider).valueOrNull ?? false;
    if (!granted) return const SizedBox.shrink();

    // Both sources degrade to an empty list while loading or on error, so the
    // card simply stays hidden until there is something real to show.
    final suggestions =
        ref.watch(usageSuggestionsProvider).valueOrNull ?? const [];
    final proposals = ref.watch(carveProposalsProvider).valueOrNull ?? const [];
    if (suggestions.isEmpty && proposals.isEmpty) {
      return const SizedBox.shrink();
    }

    final cats = ref.watch(categoriesProvider).valueOrNull ?? [];
    final screenTimeCat =
        cats.where((c) => c.name == 'Screen Time').firstOrNull;

    // Set default category to Screen Time once categories are available;
    // putIfAbsent preserves any selection the user has already made.
    if (screenTimeCat != null) {
      for (final s in suggestions) {
        _selectedCategory.putIfAbsent(s.hour, () => screenTimeCat.id);
      }
      for (final p in proposals) {
        _carveCategory.putIfAbsent(_carveKey(p), () => screenTimeCat.id);
      }
    }

    final accent = AppColors.accentForHour(DateTime.now().hour);
    final pending = ref.watch(pendingReconciliationCountProvider);

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

          // ── Carve rows: one per app, in already-logged hours ─────────
          if (proposals.isNotEmpty) ...[
            if (suggestions.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'ALREADY LOGGED',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ...proposals.map((p) => _CarveRow(
                  proposal: p,
                  cats: cats,
                  selectedCatId: _carveCategory[_carveKey(p)],
                  isConfirming: _carveConfirming.contains(_carveKey(p)),
                  onCategoryChanged: (catId) =>
                      setState(() => _carveCategory[_carveKey(p)] = catId),
                  onConfirm: () => _confirmCarve(p),
                  onDismiss: () => _dismissCarve(p),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(UsageSuggestion s) async {
    setState(() => _confirming.add(s.hour));
    final db = ref.read(appDatabaseProvider);
    try {
      // Goes through insertRetroactive so sacred real-time entries are never
      // overwritten and auto-split rules apply.
      // Record only the minutes actually detected, anchored to the top of the
      // hour — the rest of the hour stays free for the user to log by hand.
      final result = await db.logEntriesDao.insertRetroactive(
        startTime: s.bucketStart,
        endTime: s.bucketStart.add(Duration(minutes: s.totalMinutes)),
        categoryId: _selectedCategory[s.hour],
        description: s.description,
        isUsageDerived: true,
      );
      if (mounted && result.writtenMinutes == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That window is already fully logged.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Either way the bucket is now "handled": todayEntriesProvider stream
      // will update → the suggestion auto-disappears when something was
      // written; when nothing was, a real-time entry already covers the hour,
      // so the overlap check hides it too.
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

  // ── Carve rows ─────────────────────────────────────────────────────────────

  Future<void> _confirmCarve(CarveProposal p) async {
    final key = _carveKey(p);
    setState(() => _carveConfirming.add(key));
    try {
      // Shared logic: planCarve places the screen time in the hour's empty
      // space and trims the logged entry only if the hour would exceed 60.
      final outcome = await applyCarve(
        db: ref.read(appDatabaseProvider),
        proposal: p,
        categoryId: _carveCategory[key],
      );
      if (mounted && outcome == CarveOutcome.entryMissing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That entry no longer exists.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      // logEntriesForDayProvider updates → carveProposalsProvider recomputes
      // → this row disappears on its own.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not confirm: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _carveConfirming.remove(key));
    }
  }

  Future<void> _dismissCarve(CarveProposal p) async {
    await dismissCarve(db: ref.read(appDatabaseProvider), proposal: p);
    // _dismissedCarvesTodayProvider updates → carveProposalsProvider
    // recomputes → this row disappears automatically.
  }
}

// ── Shared reconcile tile ─────────────────────────────────────────────────────

/// The tile both reconcile rows render: a title line, a muted subtitle, the
/// category chip strip, and Dismiss / Confirm.
///
/// Extracted verbatim from the empty-hour suggestion row so a carve row looks
/// exactly like one — the suggestion rows themselves render an identical tree
/// to before.
class _ReconcileTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final List<Category> cats;
  final int? selectedCatId;
  final bool isConfirming;
  final void Function(int?) onCategoryChanged;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _ReconcileTile({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.cats,
    required this.selectedCatId,
    required this.isConfirming,
    required this.onCategoryChanged,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
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
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
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
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide(
                          color: sel
                              ? catColor.withValues(alpha: 0.60)
                              : Colors.white.withValues(alpha: 0.15),
                        ),
                        labelStyle: TextStyle(
                          color: sel ? Colors.white : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                    child:
                        const Text('Dismiss', style: TextStyle(fontSize: 12)),
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
                        : const Text('Confirm', style: TextStyle(fontSize: 12)),
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

// ── Empty-hour suggestion row ─────────────────────────────────────────────────

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
    return _ReconcileTile(
      title: '${fmt.format(suggestion.bucketStart)} – '
          '${fmt.format(suggestion.bucketEnd)}',
      subtitle: suggestion.description,
      accent: AppColors.accentForHour(suggestion.hour),
      cats: cats,
      selectedCatId: selectedCatId,
      isConfirming: isConfirming,
      onCategoryChanged: onCategoryChanged,
      onConfirm: onConfirm,
      onDismiss: onDismiss,
    );
  }
}

// ── Carve row: one app, in an hour that is already logged ─────────────────────

/// Offers to split one app's detected minutes out of a logged entry. Confirm
/// runs the shared [applyCarve] (planCarve + shrink/insert); Dismiss runs the
/// shared [dismissCarve]. Both are reactive — the row vanishes on its own.
class _CarveRow extends StatelessWidget {
  final CarveProposal proposal;
  final List<Category> cats;
  final int? selectedCatId;
  final bool isConfirming;
  final void Function(int?) onCategoryChanged;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _CarveRow({
    required this.proposal,
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
    final entry = proposal.loggedEntry;
    // The entry is fully contained in its bucket, so its date carries the hour.
    final hourStart = DateTime(entry.startTime.year, entry.startTime.month,
        entry.startTime.day, proposal.hour);
    final hourEnd = hourStart.add(const Duration(hours: 1));

    return _ReconcileTile(
      title: '${proposal.appLabel} ${proposal.durationMinutes}m · '
          '${fmt.format(hourStart)} – ${fmt.format(hourEnd)}',
      subtitle: entry.description.isNotEmpty
          ? 'Split out of "${entry.description}"'
          : 'Split out of your logged time',
      accent: AppColors.accentForHour(proposal.hour),
      cats: cats,
      selectedCatId: selectedCatId,
      isConfirming: isConfirming,
      onCategoryChanged: onCategoryChanged,
      onConfirm: onConfirm,
      onDismiss: onDismiss,
    );
  }
}
