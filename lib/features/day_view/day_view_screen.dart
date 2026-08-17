import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/carve_proposals_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/log_entries_provider.dart';
import '../../providers/routine_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';
import '../log_entry/log_entry_sheet.dart';
import 'widgets/entry_with_carves.dart';

class DayViewScreen extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  const DayViewScreen({super.key, this.initialDate});

  @override
  ConsumerState<DayViewScreen> createState() => _DayViewScreenState();
}

class _DayViewScreenState extends ConsumerState<DayViewScreen> {
  late DateTime _date;
  static const double _hourPx = 76.0;
  final _scrollCtrl = ScrollController();
  final Set<int> _pendingDeleteIds = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scrollTo = ((now.hour - 2).clamp(0, 21)) * _hourPx;
      _scrollCtrl.animateTo(
        scrollTo,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  void _prevDay() =>
      setState(() => _date = _date.subtract(const Duration(days: 1)));

  void _nextDay() {
    final candidate = _date.add(const Duration(days: 1));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!candidate.isAfter(today)) setState(() => _date = candidate);
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(logEntriesForDayProvider(_date));
    final catsAsync = ref.watch(categoriesProvider);
    final routineAsync = ref.watch(allRoutineSlotsProvider);
    final dayOfWeek = _date.weekday;
    final todaySlots = (routineAsync.valueOrNull ?? [])
        .where((s) => s.dayOfWeek == dayOfWeek || s.dayOfWeek == 0)
        .toList();

    // Carve proposals are today-only — no historical usage data is available.
    final carveProposals = _isToday
        ? (ref.watch(carveProposalsProvider).valueOrNull ?? <CarveProposal>[])
        : <CarveProposal>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white),
                onPressed: () => context.pop(),
              )
            : null,
        title: _DateNav(
          date: _date,
          onPrev: _prevDay,
          onNext: _nextDay,
          canGoNext: !_isToday,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded,
                color: Colors.white),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: entriesAsync.when(
            data: (entries) {
              _pendingDeleteIds.removeWhere(
                  (id) => !entries.any((e) => e.id == id));
              final visible = entries
                  .where((e) => !_pendingDeleteIds.contains(e.id))
                  .toList();
              return _Timeline(
                date: _date,
                entries: visible,
                cats: catsAsync.valueOrNull ?? [],
                routineSlots: todaySlots,
                carveProposals: carveProposals,
                isToday: _isToday,
                scrollCtrl: _scrollCtrl,
                hourPx: _hourPx,
                onEntryTap: (entry) => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useRootNavigator: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => LogEntrySheet(existing: entry),
                ),
                onShortCarveTap: (entry) => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useRootNavigator: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _CarveSheet(
                    entry: entry,
                    cats: catsAsync.valueOrNull ?? [],
                  ),
                ),
                onDeleteEntry: (entry) {
                  setState(() => _pendingDeleteIds.add(entry.id));
                  ref
                      .read(appDatabaseProvider)
                      .logEntriesDao
                      .deleteEntry(entry.id);
                },
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('$e',
                  style: const TextStyle(color: Colors.white54)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Date navigation row ──────────────────────────────────────────────────────

class _DateNav extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool canGoNext;

  const _DateNav({
    required this.date,
    required this.onPrev,
    required this.onNext,
    required this.canGoNext,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final label =
        isToday ? 'Today' : DateFormat('EEE, MMM d').format(date);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
          onPressed: onPrev,
          padding: EdgeInsets.zero,
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right_rounded,
            color: canGoNext ? Colors.white : Colors.white30,
          ),
          onPressed: canGoNext ? onNext : null,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

// ── 24-hour timeline ─────────────────────────────────────────────────────────

class _Timeline extends StatelessWidget {
  final DateTime date;
  final List<LogEntry> entries;
  final List<Category> cats;
  final List<RoutineSlot> routineSlots;
  final List<CarveProposal> carveProposals;
  final bool isToday;
  final ScrollController scrollCtrl;
  final double hourPx;
  final void Function(LogEntry) onEntryTap;
  final void Function(LogEntry) onShortCarveTap;
  final void Function(LogEntry) onDeleteEntry;

  const _Timeline({
    required this.date,
    required this.entries,
    required this.cats,
    required this.routineSlots,
    required this.carveProposals,
    required this.isToday,
    required this.scrollCtrl,
    required this.hourPx,
    required this.onEntryTap,
    required this.onShortCarveTap,
    required this.onDeleteEntry,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMinute = isToday ? now.hour * 60 + now.minute : -1;

    return SingleChildScrollView(
      controller: scrollCtrl,
      padding: const EdgeInsets.only(bottom: 100),
      child: SizedBox(
        height: hourPx * 24 + 1,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hour labels
            SizedBox(
              width: 52,
              child: Stack(
                children: List.generate(25, (h) {
                  return Positioned(
                    top: h * hourPx - 6,
                    left: 0,
                    right: 4,
                    child: Text(
                      '${h.toString().padLeft(2, '0')}:00',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Timeline body
            Expanded(
              child: Stack(
                children: [
                  // Hour dividers
                  ...List.generate(24, (h) => Positioned(
                    top: h * hourPx,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 0.5,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  )),
                  // Half-hour dividers
                  ...List.generate(24, (h) => Positioned(
                    top: h * hourPx + hourPx / 2,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 0.5,
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  )),
                  // Routine ghost blocks (behind real entries)
                  ...routineSlots.map((s) => _ghostBlock(s)),
                  // Entry blocks — rendered with pending carve proposals when present.
                  ...entries.map((entry) {
                    final proposals = carveProposals
                        .where((p) => p.loggedEntry.id == entry.id)
                        .toList();
                    return proposals.isNotEmpty
                        ? _entryBlockWithCarves(entry, proposals)
                        : _entryBlock(entry);
                  }),
                  // Current time indicator
                  if (nowMinute >= 0)
                    Positioned(
                      top: nowMinute * hourPx / 60 - 1,
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1.5,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  double _slotCoverage(RoutineSlot slot) {
    final slotStart = slot.startHour * 60;
    final slotEnd = (slot.startHour + slot.durationHours) * 60;
    final slotLen = slotEnd - slotStart;
    if (slotLen <= 0) return 0;
    int covered = 0;
    for (final e in entries) {
      final eStart = e.startTime.hour * 60 + e.startTime.minute;
      final eEnd = e.endTime.hour * 60 + e.endTime.minute;
      final overlap =
          (eEnd.clamp(slotStart, slotEnd) - eStart.clamp(slotStart, slotEnd))
              .clamp(0, slotLen);
      covered += overlap;
    }
    return covered / slotLen;
  }

  bool _hasCategoryMatch(RoutineSlot slot) {
    final slotStart = slot.startHour * 60;
    final slotEnd = (slot.startHour + slot.durationHours) * 60;
    return entries.any((e) {
      final eStart = e.startTime.hour * 60 + e.startTime.minute;
      final eEnd = e.endTime.hour * 60 + e.endTime.minute;
      return e.categoryId == slot.categoryId &&
          eStart < slotEnd &&
          eEnd > slotStart;
    });
  }

  /// Entry block that renders the logged entry split side-by-side with its
  /// pending carve proposals.  Falls back to a plain [_entryBlock] when the
  /// pixel height is too small to fit the carve UI (< 50 px).
  Widget _entryBlockWithCarves(
      LogEntry entry, List<CarveProposal> proposals) {
    final startMin = entry.startTime.hour * 60 + entry.startTime.minute;
    final endMin = (entry.endTime.hour * 60 + entry.endTime.minute)
        .clamp(startMin + 1, 1440);
    final top = startMin * hourPx / 60;
    final height =
        ((endMin - startMin) * hourPx / 60 - 2).clamp(6.0, double.infinity);

    if (height < 50) return _entryBlock(entry, carveProposals: proposals);

    return Positioned(
      top: top + 1,
      left: 2,
      right: 2,
      height: height,
      child: EntryWithCarves(
        entry: entry,
        proposals: proposals,
        cats: cats,
        onEntryTap: () => onEntryTap(entry),
      ),
    );
  }

  Widget _ghostBlock(RoutineSlot slot) {
    final slotStart = slot.startHour * 60;
    final slotEnd = (slot.startHour + slot.durationHours) * 60;
    final top = slotStart * hourPx / 60;
    final height =
        ((slotEnd - slotStart) * hourPx / 60 - 2).clamp(6.0, double.infinity);

    final cat = cats.where((c) => c.id == slot.categoryId).firstOrNull;
    final color = Color(cat?.colorValue ?? 0xFF607D8B);

    final now = DateTime.now();
    final nowMinute = isToday ? now.hour * 60 + now.minute : 1440;
    final isPast = slotEnd <= nowMinute;

    Color leftEdge;
    double edgeWidth;
    if (isPast) {
      final cov = _slotCoverage(slot);
      final match = _hasCategoryMatch(slot);
      if (cov >= 0.75 && match) {
        leftEdge = Colors.greenAccent;
        edgeWidth = 3.5;
      } else if (cov >= 0.10) {
        leftEdge = Colors.amberAccent;
        edgeWidth = 3.5;
      } else {
        leftEdge = Colors.redAccent.withValues(alpha: 0.7);
        edgeWidth = 3.5;
      }
    } else {
      leftEdge = color.withValues(alpha: 0.22);
      edgeWidth = 1.5;
    }

    return Positioned(
      top: top + 1,
      left: 2,
      right: 2,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: leftEdge, width: edgeWidth),
            top: BorderSide(color: color.withValues(alpha: 0.14), width: 0.5),
            right:
                BorderSide(color: color.withValues(alpha: 0.14), width: 0.5),
            bottom:
                BorderSide(color: color.withValues(alpha: 0.14), width: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _entryBlock(LogEntry entry,
      {List<CarveProposal> carveProposals = const []}) {
    final startMin = entry.startTime.hour * 60 + entry.startTime.minute;
    // Clamp end to midnight (1440 min) in case entry spans day boundary
    final endMin = (entry.endTime.hour * 60 + entry.endTime.minute)
        .clamp(startMin + 1, 1440);
    final top = startMin * hourPx / 60;
    final height = ((endMin - startMin) * hourPx / 60 - 2).clamp(6.0, double.infinity);

    final cat = cats.where((c) => c.id == entry.categoryId).firstOrNull;
    final color = Color(cat?.colorValue ?? 0xFF607D8B);

    final base = Dismissible(
      key: ValueKey('logentry_${entry.id}'),
      direction:
          isToday ? DismissDirection.endToStart : DismissDirection.none,
      resizeDuration: null,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.redAccent, size: 18),
      ),
      onDismissed: (_) => onDeleteEntry(entry),
      child: GestureDetector(
        onTap: () => onEntryTap(entry),
        child: GlassCard(
        borderRadius: 8,
        opacity: 0.13,
        blurSigma: 6,
        fillColor: color.withValues(alpha: 0.22),
        borderColor: color.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (entry.isRealTime && height > 28)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'LIVE',
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );

    if (carveProposals.isEmpty) {
      return Positioned(
        top: top + 1,
        left: 2,
        right: 2,
        height: height,
        child: base,
      );
    }

    // Short-entry fallback: block is too short for the inline carve UI, so
    // overlay a small amber count marker that opens the carve bottom sheet.
    // The marker is a separate tap target — block-tap still opens the edit
    // sheet, and swipe-to-delete on today still works on the base.
    return Positioned(
      top: top + 1,
      left: 2,
      right: 2,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          base,
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onShortCarveTap(entry),
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFAB40),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${carveProposals.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet: carve controls for a short entry ───────────────────────────

class _CarveSheet extends ConsumerWidget {
  final LogEntry entry;
  final List<Category> cats;

  const _CarveSheet({required this.entry, required this.cats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all =
        ref.watch(carveProposalsProvider).valueOrNull ?? const <CarveProposal>[];
    final live = all.where((p) => p.loggedEntry.id == entry.id).toList();

    final fmt = DateFormat('h:mm a');
    final header = entry.description.isNotEmpty
        ? entry.description
        : '${fmt.format(entry.startTime)} – ${fmt.format(entry.endTime)}';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: GlassCard(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                'SCREEN TIME CARVES',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                header,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              if (live.isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'All carves handled ✓',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context,
                                rootNavigator: true)
                            .pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.14),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                )
              else
                CarveActions(
                  entry: entry,
                  proposals: live,
                  cats: cats,
                  expandProposals: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
