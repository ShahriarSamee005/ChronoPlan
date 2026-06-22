import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/settings_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: settingsAsync.when(
            data: (settings) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              children: [
                _SectionLabel('AI Assistant'),
                const _ApiKeyCard(),
                const SizedBox(height: 12),
                _PersonaCard(current: settings.aiPersona),
                const SizedBox(height: 24),
                _SectionLabel('Notifications'),
                _NotifCard(settings: settings),
              ],
            ),
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

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      );
}

// ── API key card ──────────────────────────────────────────────────────────────

class _ApiKeyCard extends ConsumerStatefulWidget {
  const _ApiKeyCard();

  @override
  ConsumerState<_ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends ConsumerState<_ApiKeyCard> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    ref.read(claudeApiKeyProvider.future).then((key) {
      if (mounted && key != null && key.isNotEmpty) {
        _ctrl.text = key;
      }
    });
    _ctrl.addListener(() => setState(() => _dirty = true));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      opacity: 0.10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Claude API Key',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: 'sk-ant-…',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _dirty ? _save : null,
                  child: const Text('Save key'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _clear,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent, width: 1),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty) return;
    await ref.read(apiKeyNotifierProvider.notifier).saveKey(key);
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved')),
      );
    }
  }

  Future<void> _clear() async {
    await ref.read(apiKeyNotifierProvider.notifier).clearKey();
    _ctrl.clear();
    setState(() => _dirty = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key cleared')),
      );
    }
  }
}

// ── Persona card ──────────────────────────────────────────────────────────────

class _PersonaCard extends ConsumerWidget {
  final String current;
  const _PersonaCard({required this.current});

  static const _personas = [
    ('friendly', 'Friendly', Icons.sentiment_very_satisfied_outlined),
    ('drill', 'Drill Sergeant', Icons.fitness_center_outlined),
    ('neutral', 'Neutral', Icons.balance_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      opacity: 0.10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Persona',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: _personas.map((p) {
              final (value, label, icon) = p;
              final selected = current == value;
              return FilterChip(
                avatar: Icon(icon,
                    size: 14,
                    color: selected ? Colors.white : AppColors.textMuted),
                label: Text(label),
                selected: selected,
                onSelected: (_) => ref
                    .read(settingsNotifierProvider.notifier)
                    .setAiPersona(value),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Notification card ─────────────────────────────────────────────────────────

class _NotifCard extends ConsumerStatefulWidget {
  final UserSetting settings;
  const _NotifCard({required this.settings});

  @override
  ConsumerState<_NotifCard> createState() => _NotifCardState();
}

class _NotifCardState extends ConsumerState<_NotifCard> {
  late String _mode;
  late int _interval;

  /// Map legacy DB values to the new two-option model.
  static String _normalise(String raw) {
    if (raw == 'strict') return 'custom';
    if (raw == 'gentle') return 'hourly';
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _mode = _normalise(widget.settings.reminderMode);
    _interval = widget.settings.strictIntervalMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      opacity: 0.10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reminder Mode',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'hourly',
                label: Text('Hourly'),
                icon: Icon(Icons.schedule_rounded, size: 15),
              ),
              ButtonSegment(
                value: 'custom',
                label: Text('Custom'),
                icon: Icon(Icons.tune_rounded, size: 15),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (v) {
              final newMode = v.first;
              setState(() => _mode = newMode);
              ref
                  .read(settingsNotifierProvider.notifier)
                  .setReminderMode(newMode);
            },
          ),
          if (_mode == 'custom') ...[
            const SizedBox(height: 14),
            Text(
              'Remind every $_interval minutes',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            Slider(
              value: _interval.toDouble(),
              min: 30,
              max: 180,
              divisions: 10,
              label: '$_interval min',
              onChanged: (v) => setState(() => _interval = v.round()),
              onChangeEnd: (v) => ref
                  .read(settingsNotifierProvider.notifier)
                  .setCustomInterval(v.round()),
            ),
          ],
          if (_mode == 'hourly') ...[
            const SizedBox(height: 10),
            const Text(
              'You\'ll get a nudge at the top of every hour.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

