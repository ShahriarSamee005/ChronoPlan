import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/usage_stats/usage_stats_service.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// TEMPORARY DEBUG SCREEN — diagnostic tool for the Usage Stats pipeline.
///
/// Reachable via a long-press on the "ChronoPlan" title in the Dashboard app
/// bar (see dashboard_screen.dart) — deliberately not in the main flow.
/// Safe to delete this whole file (and the long-press hook + route) once the
/// queryEvents pipeline is trusted; nothing else depends on it.
///
/// Shows, for a selectable hour of today:
///   A. RAW EVENTS   — every event type, completely unfiltered.
///   B. SESSIONS     — reconstructed foreground sessions overlapping the hour.
///   C. FINAL LIST   — what the UI actually consumes, plus what each
///                     filtering stage (user-facing check, 10-min threshold)
///                     removed and why.
/// ─────────────────────────────────────────────────────────────────────────
class UsageDebugScreen extends StatefulWidget {
  const UsageDebugScreen({super.key});

  @override
  State<UsageDebugScreen> createState() => _UsageDebugScreenState();
}

class _UsageDebugScreenState extends State<UsageDebugScreen> {
  final _service = UsageStatsService();
  late int _hour;
  Future<UsageDebugSnapshot>? _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _hour = now.hour > 0 ? now.hour - 1 : 0; // default to the last full hour
    _load();
  }

  void _load() {
    setState(() {
      _future = _service.getDebugSnapshot(DateTime.now(), _hour);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2A),
        title: const Text('Usage Stats Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: 'Re-run query',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.orange.withValues(alpha: 0.18),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text(
              'TEMPORARY DIAGNOSTIC VIEW — not part of the normal app flow',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _HourSelector(
            hour: _hour,
            maxHour: DateTime.now().hour,
            onChanged: (h) {
              _hour = h;
              _load();
            },
          ),
          const Divider(color: Colors.white24, height: 1),
          Expanded(
            child: FutureBuilder<UsageDebugSnapshot>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  );
                }
                final data = snap.data;
                if (data == null) {
                  return const Center(
                    child: Text('No data (not Android, or query failed).',
                        style: TextStyle(color: Colors.white54)),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (data.guardViolations.isNotEmpty) ...[
                      _GuardViolationSection(violations: data.guardViolations),
                      const SizedBox(height: 20),
                    ],
                    _SectionHeader(
                      'A. RAW EVENTS (unfiltered) — ${data.rawEvents.length}',
                    ),
                    if (data.rawEvents.isEmpty)
                      const _EmptyNote('No events in this hour.'),
                    ...data.rawEvents.map(_RawEventRow.new),
                    const SizedBox(height: 20),
                    _SectionHeader(
                      'B. RECONSTRUCTED SESSIONS — ${data.sessions.length}',
                    ),
                    if (data.sessions.isEmpty)
                      const _EmptyNote('No sessions overlap this hour.'),
                    ...data.sessions.map(_SessionRow.new),
                    const SizedBox(height: 20),
                    _SectionHeader(
                      'C. FINAL LIST (after label + filter + threshold)',
                    ),
                    _StageSummary(stages: data.stages),
                    const SizedBox(height: 8),
                    if (data.finalEntries.isEmpty)
                      const _EmptyNote('Nothing survives all stages for this hour.'),
                    ...data.finalEntries.map(_FinalEntryRow.new),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hour selector ────────────────────────────────────────────────────────────

class _HourSelector extends StatelessWidget {
  final int hour;
  final int maxHour;
  final ValueChanged<int> onChanged;

  const _HourSelector({
    required this.hour,
    required this.maxHour,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: maxHour + 1,
        itemBuilder: (context, h) {
          final selected = h == hour;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Text('${h.toString().padLeft(2, '0')}:00'),
              selected: selected,
              onSelected: (_) => onChanged(h),
              labelStyle: TextStyle(
                color: selected ? Colors.black : Colors.white70,
                fontSize: 12,
              ),
              selectedColor: Colors.orangeAccent,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
          );
        },
      ),
    );
  }
}

// ── Shared row widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.orangeAccent,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text,
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
    );
  }
}

final _timeFmt = DateFormat('HH:mm:ss');

class _RawEventRow extends StatelessWidget {
  final DebugRawEvent e;
  const _RawEventRow(this.e);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(_timeFmt.format(e.timestamp),
                style: const _Mono(Colors.white)),
          ),
          SizedBox(
            width: 130,
            child: Text('${e.timestamp.millisecondsSinceEpoch}',
                style: const _Mono(Colors.white38)),
          ),
          SizedBox(
            width: 120,
            child: Text(e.typeName,
                style: const _Mono(Colors.lightBlueAccent),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: Text(e.packageName,
                style: const _Mono(Colors.white70),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final DebugSession s;
  const _SessionRow(this.s);

  @override
  Widget build(BuildContext context) {
    final flags = <String>[
      if (s.openEnded) 'OPEN-ENDED',
      if (s.clamped) 'CLAMPED',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(s.packageName,
                style: const _Mono(Colors.white),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 130,
            child: Text(
              '${_timeFmt.format(s.start)} → ${_timeFmt.format(s.end)}',
              style: const _Mono(Colors.white70),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text('${s.durationMinutes}m',
                style: const _Mono(Colors.greenAccent)),
          ),
          Expanded(
            flex: 2,
            child: Text(
              flags.isEmpty ? '' : flags.join(' '),
              style: const _Mono(Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageSummary extends StatelessWidget {
  final List<DebugFilterStage> stages;
  const _StageSummary({required this.stages});

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) {
      return const _EmptyNote('No packages had any usage this hour.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: stages.map((s) {
        final reasons = <String>[
          if (!s.userFacing) 'not user-facing (launcher/system/own app)',
          if (!s.meetsThreshold) '< 10 min threshold',
        ];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                s.includedInFinal
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                size: 14,
                color: s.includedInFinal ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 150,
                child: Text(s.label,
                    style: const _Mono(Colors.white),
                    overflow: TextOverflow.ellipsis),
              ),
              SizedBox(
                width: 50,
                child: Text('${s.rawMinutes}m', style: const _Mono(Colors.white70)),
              ),
              Expanded(
                child: Text(
                  reasons.isEmpty ? 'kept' : reasons.join(', '),
                  style: TextStyle(
                    color: s.includedInFinal ? Colors.white38 : Colors.redAccent,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _GuardViolationSection extends StatelessWidget {
  final List<UsageGuardViolation> violations;
  const _GuardViolationSection({required this.violations});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.14),
        border: Border.all(color: Colors.redAccent, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: Colors.redAccent),
              const SizedBox(width: 6),
              Text('GUARD TRIPPED — ${violations.length} clamp(s) this hour',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          ...violations.map((v) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${v.pkg}: ${v.rawMinutes}m → clamped to ${v.clampedTo}m',
                  style: const _Mono(Colors.redAccent),
                ),
              )),
        ],
      ),
    );
  }
}

class _FinalEntryRow extends StatelessWidget {
  final AppUsageEntry e;
  const _FinalEntryRow(this.e);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(e.appLabel, style: const _Mono(Colors.white)),
          ),
          Text('${e.durationMinutes}m',
              style: const _Mono(Colors.greenAccent)),
        ],
      ),
    );
  }
}

class _Mono extends TextStyle {
  const _Mono(Color color)
      : super(color: color, fontSize: 11, fontFamily: 'monospace');
}
