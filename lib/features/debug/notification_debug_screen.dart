import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/notifications/notification_service.dart';
import '../../providers/database_provider.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// TEMPORARY DEBUG SCREEN — what reminder alarms are actually armed.
///
/// Diagnostic for "no reminders after the sleep toggle". Read-only: it
/// schedules and cancels nothing.
///
/// Reachable from the bell icon in the Usage Stats Debug app bar (Screen Time
/// → long-press the title). Safe to delete this file and that one IconButton;
/// nothing else depends on it.
///
/// CAVEAT: `pendingNotificationRequests()` on Android reads the plugin's own
/// SharedPreferences cache, NOT AlarmManager. An entry here means "the plugin
/// believes it armed this". A force-stop clears AlarmManager but not that
/// cache. Cross-check with: adb shell dumpsys alarm | grep -i chronoplan
/// ─────────────────────────────────────────────────────────────────────────
class NotificationDebugScreen extends ConsumerStatefulWidget {
  const NotificationDebugScreen({super.key});

  @override
  ConsumerState<NotificationDebugScreen> createState() =>
      _NotificationDebugScreenState();
}

class _Line {
  final String label;
  final String value;
  const _Line(this.label, this.value);
}

class _Snapshot {
  final List<_Line> clock;
  final List<_Line> settings;
  final List<_Line> permissions;
  final List<PendingNotificationRequest> pending;
  final List<_Line> pendingSummary;

  /// Hourly ids only: the next h:00 in tz.local, as the device clock shows
  /// it. DERIVED from the id — the plugin does not report fire times.
  final Map<int, String> derivedFire;

  const _Snapshot({
    required this.clock,
    required this.settings,
    required this.permissions,
    required this.pending,
    required this.pendingSummary,
    required this.derivedFire,
  });

  String toText() {
    final b = StringBuffer('ChronoPlan reminder debug (TEMPORARY)\n');
    void section(String title, List<_Line> lines) {
      b.writeln('\n== $title');
      for (final l in lines) {
        b.writeln('${l.label}: ${l.value}');
      }
    }

    section('CLOCK', clock);
    section('SETTINGS', settings);
    section('PERMISSIONS', permissions);
    section('PENDING (plugin cache)', pendingSummary);
    for (final p in pending) {
      final d = derivedFire[p.id];
      b.writeln('${p.id} | ${p.title} | ${p.body}'
          '${d == null ? '' : ' | derived: $d'}');
    }
    return b.toString();
  }
}

class _NotificationDebugScreenState
    extends ConsumerState<NotificationDebugScreen> {
  Future<_Snapshot>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _future = _collect());

  Future<String> _probe(Future<Object?> Function() f) async {
    try {
      return '${await f()}';
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  Future<_Snapshot> _collect() async {
    final deviceNow = DateTime.now();
    final tzNow = tz.TZDateTime.now(tz.local);

    final s = await ref.read(appDatabaseProvider).getSettings();
    final service = ref.read(notificationServiceProvider);

    // Singleton — the same instance NotificationService drives.
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final granted = await _probe(service.isPermissionGranted);
    final exact =
        await _probe(() async => android?.canScheduleExactNotifications());
    final channel = await _probe(() async {
      final chans = await android?.getNotificationChannels();
      if (chans == null) return 'null (no Android impl)';
      final c = chans.where((c) => c.id == 'chronoplan_reminders');
      if (c.isEmpty) return 'MISSING';
      final imp = c.first.importance;
      return '${imp.name} (${imp.value})'
          '${imp == Importance.none ? '  ← CHANNEL BLOCKED' : ''}';
    });

    List<PendingNotificationRequest> pending;
    String pendingError = '';
    try {
      pending = await plugin.pendingNotificationRequests();
    } catch (e) {
      pending = const [];
      pendingError = 'ERROR: $e';
    }
    pending.sort((a, b) => a.id.compareTo(b.id));

    final ids = pending.map((p) => p.id).toSet();
    final hourly = ids.where((id) => id >= 300 && id <= 323).toList();
    final interval = ids.where((id) => id >= 100 && id <= 147).toList();
    final other = ids.difference({...hourly, ...interval}).toList()..sort();
    final missingHourly = [
      for (var id = 300; id <= 323; id++)
        if (!ids.contains(id)) id,
    ];

    final derived = <int, String>{};
    for (final id in hourly) {
      final h = id - 300;
      var f = tz.TZDateTime(
          tz.local, tzNow.year, tzNow.month, tzNow.day, h);
      if (f.isBefore(tzNow)) f = f.add(const Duration(days: 1));
      final dev = DateTime.fromMillisecondsSinceEpoch(f.millisecondsSinceEpoch);
      derived[id] = '${_two(h)}:00 ${tz.local.name} → device '
          '${_dayTag(dev, deviceNow)} ${_two(dev.hour)}:${_two(dev.minute)}';
    }

    return _Snapshot(
      clock: [
        _Line('DateTime.now()', '$deviceNow'),
        _Line('DateTime.now().timeZoneOffset', '${deviceNow.timeZoneOffset}'),
        _Line('DateTime.now().timeZoneName', deviceNow.timeZoneName),
        _Line('tz.local.name', tz.local.name),
        _Line('tz.TZDateTime.now(tz.local)', '$tzNow'),
      ],
      settings: [
        _Line('reminderMode', s.reminderMode),
        _Line('strictIntervalMinutes', '${s.strictIntervalMinutes}'),
        _Line('sleepModeActive', '${s.sleepModeActive}'),
        _Line('sleepModeStartedAt', '${s.sleepModeStartedAt}'),
      ],
      permissions: [
        _Line('notifications enabled (isPermissionGranted)', granted),
        _Line('canScheduleExactNotifications', exact),
        _Line('channel chronoplan_reminders importance', channel),
      ],
      pending: pending,
      pendingSummary: [
        if (pendingError.isNotEmpty) _Line('pendingNotificationRequests', pendingError),
        _Line('total', '${pending.length}'),
        _Line('hourly 300–323', '${hourly.length}'),
        _Line('interval 100–147', '${interval.length}'),
        _Line('other ids', other.isEmpty ? '—' : other.join(', ')),
        _Line('hourly ids NOT armed',
            missingHourly.isEmpty ? '—' : missingHourly.join(', ')),
      ],
      derivedFire: derived,
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dayTag(DateTime t, DateTime now) {
    final d = DateTime(t.year, t.month, t.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    return d == 0 ? 'today' : d == 1 ? 'tmrw ' : '+${d}d  ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2A),
        title: const Text('Reminder Alarms Debug'),
        actions: [
          FutureBuilder<_Snapshot>(
            future: _future,
            builder: (context, snap) => IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copy dump',
              onPressed: snap.data == null
                  ? null
                  : () {
                      Clipboard.setData(
                          ClipboardData(text: snap.data!.toText()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Dump copied')),
                      );
                    },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: 'Re-read',
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
              'TEMPORARY DIAGNOSTIC VIEW — read-only. Pending list is the '
              "plugin's cache, not AlarmManager.",
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<_Snapshot>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Collect failed: ${snap.error}',
                        style: const _Mono(Colors.redAccent)),
                  );
                }
                final data = snap.data;
                if (data == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const _Header('CLOCK'),
                    ...data.clock.map(_KeyValue.new),
                    const SizedBox(height: 14),
                    const _Header('SETTINGS'),
                    ...data.settings.map(_KeyValue.new),
                    const SizedBox(height: 14),
                    const _Header('PERMISSIONS'),
                    ...data.permissions.map(_KeyValue.new),
                    const SizedBox(height: 14),
                    const _Header('PENDING (plugin cache)'),
                    ...data.pendingSummary.map(_KeyValue.new),
                    const SizedBox(height: 8),
                    const Text(
                      'id · title · body   (derived = computed from id, '
                      'not read from the OS)',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    ...data.pending.map(
                        (p) => _PendingRow(p, data.derivedFire[p.id])),
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

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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

class _KeyValue extends StatelessWidget {
  final _Line line;
  const _KeyValue(this.line);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '${line.label}: ', style: const _Mono(Colors.white54)),
          TextSpan(text: line.value, style: const _Mono(Colors.white)),
        ]),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final PendingNotificationRequest p;
  final String? derived;
  const _PendingRow(this.p, this.derived);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '${p.id}  ', style: const _Mono(Colors.greenAccent)),
              TextSpan(text: '${p.title}', style: const _Mono(Colors.white)),
              if (derived != null)
                TextSpan(
                    text: '   $derived',
                    style: const _Mono(Colors.lightBlueAccent)),
            ]),
          ),
          Text(
            '${p.body}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const _Mono(Colors.white38),
          ),
        ],
      ),
    );
  }
}

class _Mono extends TextStyle {
  const _Mono(Color color)
      : super(color: color, fontSize: 11, fontFamily: 'monospace');
}
