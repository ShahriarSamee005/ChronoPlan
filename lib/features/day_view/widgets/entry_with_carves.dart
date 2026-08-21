import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../core/usage_stats/carve_planner.dart';
import '../../../core/usage_stats/carve_proposal.dart';
import '../../../providers/database_provider.dart';

/// Renders a logged entry split side-by-side with its pending carve proposal(s).
///
/// Left column (58%): the existing logged entry, tappable to edit.
/// Right column (42%): pending carve proposals via [CarveActions] in inline
/// (expanded-per-proposal) mode.
///
/// This widget is placed inside the _Timeline Stack at the same Positioned
/// coordinates as a normal entry block, so it covers the full entry time range.
class EntryWithCarves extends StatelessWidget {
  final LogEntry entry;
  final List<CarveProposal> proposals;
  final List<Category> cats;
  final VoidCallback onEntryTap;

  const EntryWithCarves({
    super.key,
    required this.entry,
    required this.proposals,
    required this.cats,
    required this.onEntryTap,
  });

  @override
  Widget build(BuildContext context) {
    final entryCat =
        cats.where((c) => c.id == entry.categoryId).firstOrNull;
    final entryColor = Color(entryCat?.colorValue ?? 0xFF607D8B);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Logged entry (left, 58%) ──────────────────────────────────────
        Expanded(
          flex: 58,
          child: GestureDetector(
            onTap: onEntryTap,
            child: GlassCard(
              borderRadius: 8,
              opacity: 0.13,
              blurSigma: 6,
              fillColor: entryColor.withValues(alpha: 0.22),
              borderColor: entryColor.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.description.isNotEmpty)
                    Flexible(
                      child: Text(
                        entry.description,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        // ── Pending carve proposals (right, 42%) ─────────────────────────
        Expanded(
          flex: 42,
          child: CarveActions(
            entry: entry,
            proposals: proposals,
            cats: cats,
            expandProposals: true,
          ),
        ),
      ],
    );
  }
}

// ── Shared carve controls (state + confirm/dismiss + rendering) ──────────────

/// Reusable carve UI: owns the per-proposal selected-category map and the
/// in-flight confirming set, and drives the shared confirm/dismiss logic.
///
/// [expandProposals] = true: inline layout, each proposal gets an equal
/// [Expanded] slice of a bounded-height [Column] (used by [EntryWithCarves]).
/// [expandProposals] = false: sheet layout, proposals stack at intrinsic
/// height with a small gap between them.
class CarveActions extends ConsumerStatefulWidget {
  final LogEntry entry;
  final List<CarveProposal> proposals;
  final List<Category> cats;
  final bool expandProposals;

  const CarveActions({
    super.key,
    required this.entry,
    required this.proposals,
    required this.cats,
    required this.expandProposals,
  });

  @override
  ConsumerState<CarveActions> createState() => _CarveActionsState();
}

class _CarveActionsState extends ConsumerState<CarveActions> {
  // packageName → selected categoryId (null = none)
  final Map<String, int?> _selectedCatId = {};
  // packageNames with in-flight confirm requests
  final Set<String> _confirming = {};

  @override
  Widget build(BuildContext context) {
    final screenTimeCat =
        widget.cats.where((c) => c.name == 'Screen Time').firstOrNull;

    // Default to Screen Time once cats are available; preserve any user selection.
    if (screenTimeCat != null) {
      for (final p in widget.proposals) {
        _selectedCatId.putIfAbsent(p.packageName, () => screenTimeCat.id);
      }
    }

    if (widget.expandProposals) {
      return Column(
        children: widget.proposals
            .map(
              (p) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _CarveProposalBlock(
                    proposal: p,
                    cats: widget.cats,
                    selectedCatId: _selectedCatId[p.packageName],
                    isConfirming: _confirming.contains(p.packageName),
                    onCategoryChanged: (id) =>
                        setState(() => _selectedCatId[p.packageName] = id),
                    onConfirm: () => _confirm(p),
                    onDismiss: () => _dismiss(p),
                  ),
                ),
              ),
            )
            .toList(),
      );
    }

    // Sheet layout: intrinsic heights, 8-px gap between blocks.
    final children = <Widget>[];
    for (var i = 0; i < widget.proposals.length; i++) {
      final p = widget.proposals[i];
      children.add(_CarveProposalBlock(
        proposal: p,
        cats: widget.cats,
        selectedCatId: _selectedCatId[p.packageName],
        isConfirming: _confirming.contains(p.packageName),
        onCategoryChanged: (id) =>
            setState(() => _selectedCatId[p.packageName] = id),
        onConfirm: () => _confirm(p),
        onDismiss: () => _dismiss(p),
      ));
      if (i < widget.proposals.length - 1) {
        children.add(const SizedBox(height: 8));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Future<void> _confirm(CarveProposal proposal) async {
    setState(() => _confirming.add(proposal.packageName));
    final db = ref.read(appDatabaseProvider);

    try {
      // Re-fetch the current entry: a previous confirm on the same entry may
      // have already shrunk it, so we must not use the stale proposal snapshot.
      final current = await db.logEntriesDao.getById(proposal.loggedEntry.id);
      if (current == null) {
        _showSnack('That entry no longer exists.');
        return;
      }

      if (proposal.durationMinutes <= 0) {
        _showSnack('Nothing to add for this app.');
        return;
      }

      final catId = _selectedCatId[proposal.packageName];

      // The screen time goes into the hour's EMPTY space — the logged entry is
      // only trimmed (from its end, never below 1 min) when the hour would
      // otherwise exceed 60. It is never moved, repurposed, or erased.
      // Placement within each gap is approximate — queryEvents gives us total
      // session duration in the bucket, not where in the hour it occurred.
      final hourStart = DateTime(
        current.startTime.year,
        current.startTime.month,
        current.startTime.day,
        current.startTime.hour,
      );
      final plan = planCarve(
        entryStart: current.startTime,
        entryEnd: current.endTime,
        hourStart: hourStart,
        screenMinutes: proposal.durationMinutes,
      );

      // Shrink the entry first so the freed minutes are actually free.
      if (plan.newEntryEnd != current.endTime) {
        await db.logEntriesDao.updateEntry(LogEntriesCompanion(
          id: Value(current.id),
          endTime: Value(plan.newEntryEnd),
        ));
      }
      // Insert each screen-time block through the normal retroactive path.
      for (final (blockStart, blockEnd) in plan.screenBlocks) {
        await db.logEntriesDao.insertRetroactive(
          startTime: blockStart,
          endTime: blockEnd,
          categoryId: catId,
          description: proposal.appLabel,
          isUsageDerived: true,
        );
      }
      // The logEntriesForDayProvider stream auto-updates → _Timeline rebuilds
      // → the bucket now holds more than one entry → carveProposalsProvider
      // drops it.
    } catch (e) {
      _showSnack('Could not confirm: $e');
    } finally {
      if (mounted) setState(() => _confirming.remove(proposal.packageName));
    }
  }

  Future<void> _dismiss(CarveProposal proposal) async {
    await ref
        .read(appDatabaseProvider)
        .dismissedCarvesDao
        .dismiss(DateTime.now(), proposal.hour, proposal.packageName);
    // _dismissedCarvesTodayProvider stream updates → carveProposalsProvider
    // recomputes → this proposal row disappears automatically.
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
}

// ── Pending carve block ───────────────────────────────────────────────────────

class _CarveProposalBlock extends StatelessWidget {
  final CarveProposal proposal;
  final List<Category> cats;
  final int? selectedCatId;
  final bool isConfirming;
  final void Function(int?) onCategoryChanged;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _CarveProposalBlock({
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
    final accent = AppColors.accentForHour(proposal.hour);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFAB40).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFAB40).withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top: app label + duration
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${proposal.appLabel} ${proposal.durationMinutes}m',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              _CompactCategoryPicker(
                cats: cats,
                selectedCatId: selectedCatId,
                onChanged: onCategoryChanged,
              ),
            ],
          ),
          // Bottom: confirm / dismiss buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: isConfirming ? null : onDismiss,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '✕',
                      style: TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: GestureDetector(
                  onTap: isConfirming ? null : onConfirm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: isConfirming
                        ? const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 1.5),
                          )
                        : const Text(
                            '✓',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Compact category picker ───────────────────────────────────────────────────

class _CompactCategoryPicker extends StatelessWidget {
  final List<Category> cats;
  final int? selectedCatId;
  final void Function(int?) onChanged;

  const _CompactCategoryPicker({
    required this.cats,
    required this.selectedCatId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = cats.where((c) => c.id == selectedCatId).firstOrNull;
    final catColor =
        selected != null ? Color(selected.colorValue) : Colors.white38;

    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: catColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              selected?.name ?? 'Category',
              style: TextStyle(
                color: catColor,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Icon(Icons.expand_more_rounded, color: catColor, size: 10),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _CategoryPickerSheet(
        cats: cats,
        selectedId: selectedCatId,
        onSelected: (id) {
          Navigator.of(sheetCtx, rootNavigator: true).pop();
          onChanged(id);
        },
      ),
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  final List<Category> cats;
  final int? selectedId;
  final void Function(int?) onSelected;

  const _CategoryPickerSheet({
    required this.cats,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'SELECT CATEGORY',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: cats.map((cat) {
                  final sel = cat.id == selectedId;
                  return FilterChip(
                    label: Text(cat.name),
                    selected: sel,
                    onSelected: (_) => onSelected(cat.id),
                    avatar: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Color(cat.colorValue),
                        shape: BoxShape.circle,
                      ),
                    ),
                    selectedColor: Color(cat.colorValue).withValues(alpha: 0.22),
                    checkmarkColor: Color(cat.colorValue),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
