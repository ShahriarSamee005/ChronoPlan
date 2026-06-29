import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass_card.dart';
import '../../../core/usage_stats/carve_proposal.dart';
import '../../../providers/database_provider.dart';

/// Renders a logged entry split side-by-side with its pending carve proposal(s).
///
/// Left column (58%): the existing logged entry, tappable to edit.
/// Right column (42%): one block per pending carve proposal, each in a clearly
/// PENDING/unconfirmed visual state (amber tint + dashed-style border).
///
/// Confirm shrinks the original entry and inserts the carved block.
/// Dismiss persists the (date, hour, packageName) so the proposal never reappears.
///
/// This widget is placed inside the _Timeline Stack at the same Positioned
/// coordinates as a normal entry block, so it covers the full entry time range.
class EntryWithCarves extends ConsumerStatefulWidget {
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
  ConsumerState<EntryWithCarves> createState() => _EntryWithCarvesState();
}

class _EntryWithCarvesState extends ConsumerState<EntryWithCarves> {
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

    final entryCat =
        widget.cats.where((c) => c.id == widget.entry.categoryId).firstOrNull;
    final entryColor = Color(entryCat?.colorValue ?? 0xFF607D8B);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Logged entry (left, 58%) ──────────────────────────────────────
        Expanded(
          flex: 58,
          child: GestureDetector(
            onTap: widget.onEntryTap,
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
                  if (widget.entry.description.isNotEmpty)
                    Flexible(
                      child: Text(
                        widget.entry.description,
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
          child: Column(
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
          ),
        ),
      ],
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
        _showSnack('Entry was already fully carved.');
        return;
      }

      final entryDuration =
          current.endTime.difference(current.startTime).inMinutes;
      final carveMinutes = proposal.durationMinutes.clamp(0, entryDuration);

      if (carveMinutes <= 0) {
        _showSnack('Nothing left to carve from this entry.');
        return;
      }

      final catId = _selectedCatId[proposal.packageName];

      // Carve M minutes from the END of the current entry.
      // Placement within the hour is approximate — queryEvents gives us total
      // session duration in the bucket, not where in the hour it occurred.
      final carveStart =
          current.endTime.subtract(Duration(minutes: carveMinutes));
      final carveEnd = current.endTime;

      if (carveMinutes >= entryDuration) {
        // Entry is fully consumed — repurpose it as the carved entry rather
        // than deleting and re-inserting to preserve the row ID.
        await db.logEntriesDao.updateEntry(LogEntriesCompanion(
          id: Value(current.id),
          categoryId: Value(catId),
          description: Value(proposal.appLabel),
          startTime: Value(carveStart),
          endTime: Value(carveEnd),
        ));
      } else {
        // Shrink the original entry first so the carved slot is free.
        await db.logEntriesDao.updateEntry(LogEntriesCompanion(
          id: Value(current.id),
          endTime: Value(carveStart),
        ));
        // Insert the carved block through the normal retroactive path.
        await db.logEntriesDao.insertRetroactive(
          startTime: carveStart,
          endTime: carveEnd,
          categoryId: catId,
          description: proposal.appLabel,
        );
      }
      // The logEntriesForDayProvider stream auto-updates → _Timeline rebuilds
      // → the bucket now has two entries → carveProposalsProvider drops it.
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
