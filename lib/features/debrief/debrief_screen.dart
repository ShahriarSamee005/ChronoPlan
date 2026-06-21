import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../../providers/categories_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/intentions_provider.dart';
import '../../providers/log_entries_provider.dart';
import '../../providers/routine_provider.dart';
import '../../core/ai/claude_service.dart';
import '../../providers/settings_provider.dart';
import '../dashboard/widgets/time_gradient_background.dart';

class DebriefScreen extends ConsumerStatefulWidget {
  const DebriefScreen({super.key});

  @override
  ConsumerState<DebriefScreen> createState() => _DebriefScreenState();
}

class _DebriefScreenState extends ConsumerState<DebriefScreen> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, String>> _messages = [];
  String _streamingText = '';
  bool _isStreaming = false;
  bool _contextLoaded = false;
  StreamSubscription<String>? _streamSub;

  @override
  void dispose() {
    _streamSub?.cancel();
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _buildContextPrompt({
    required List<LogEntry> entries,
    required List<Category> cats,
    required List<RoutineSlot> routine,
    required DailyIntention? intention,
  }) {
    final today = DateTime.now();
    final dayOfWeek = today.weekday;
    final todayRoutine = routine
        .where((s) => s.dayOfWeek == dayOfWeek || s.dayOfWeek == 0)
        .toList()
      ..sort((a, b) => a.startHour.compareTo(b.startHour));

    final buf = StringBuffer();
    buf.writeln(
        'TODAY\'S CONTEXT — ${DateFormat('EEEE, MMMM d, y').format(today)}');
    buf.writeln();
    final intentionText = intention?.intention.isNotEmpty == true
        ? intention!.intention
        : 'Not set';
    buf.writeln('Morning intention: $intentionText');
    final verdict = intention?.verdictPositive;
    buf.writeln(
        'Day verdict: ${verdict == null ? 'Not yet rated' : verdict ? 'Good day (👍)' : 'Tough day (👎)'}');
    buf.writeln();

    final sorted = entries.toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    buf.writeln('LOGGED ENTRIES (${entries.length} total):');
    if (sorted.isEmpty) {
      buf.writeln('  No entries logged today.');
    } else {
      for (final e in sorted) {
        final cat = cats.where((c) => c.id == e.categoryId).firstOrNull;
        final start = DateFormat('HH:mm').format(e.startTime);
        final end = DateFormat('HH:mm').format(e.endTime);
        final mins = e.endTime.difference(e.startTime).inMinutes;
        final desc =
            e.description.isNotEmpty ? e.description : '(no description)';
        buf.writeln(
            '  $start–$end | ${cat?.name ?? 'Uncategorized'} | $desc | ${mins}min');
      }
    }

    buf.writeln();
    buf.writeln('ROUTINE PLAN FOR TODAY:');
    if (todayRoutine.isEmpty) {
      buf.writeln('  No routine set for today.');
    } else {
      for (final s in todayRoutine) {
        final cat = cats.where((c) => c.id == s.categoryId).firstOrNull;
        final endH = s.startHour + s.durationHours;
        final label = s.label.isNotEmpty ? ' | ${s.label}' : '';
        buf.writeln(
            '  ${s.startHour.toString().padLeft(2, '0')}:00–${endH.toString().padLeft(2, '0')}:00'
            ' | ${cat?.name ?? 'Unknown'}$label');
      }
    }
    return buf.toString();
  }

  void _kickOff(String contextPrompt) {
    if (_contextLoaded) return;
    _contextLoaded = true;

    final service = ref.read(claudeServiceProvider);
    if (service == null) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content':
              'Set up your Claude API key in Settings → Profile to enable AI coaching.',
        });
      });
      return;
    }

    const openingMsg =
        'Please give me a concise end-of-day debrief based on today\'s data.';
    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'user', 'content': openingMsg});
      _isStreaming = true;
      _streamingText = '';
    });

    _doStream(_messages, contextPrompt, service);
  }

  void _sendMessage(String text, String contextPrompt) {
    final service = ref.read(claudeServiceProvider);
    if (service == null || _isStreaming || text.trim().isEmpty) return;

    _controller.clear();
    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'user', 'content': text.trim()});
      _isStreaming = true;
      _streamingText = '';
    });
    _scrollToBottom();

    _doStream(_messages, contextPrompt, service);
  }

  void _doStream(
    List<Map<String, String>> messages,
    String contextPrompt,
    ClaudeService service,
  ) {
    final buf = StringBuffer();

    _streamSub?.cancel();
    _streamSub = service.debriefStreamSSE(messages, contextPrompt).listen(
      (token) {
        if (!mounted) return;
        buf.write(token);
        setState(() => _streamingText = buf.toString());
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': buf.isEmpty ? '…' : buf.toString(),
          });
          _streamingText = '';
          _isStreaming = false;
        });
        _scrollToBottom();
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': buf.isEmpty ? '…' : buf.toString(),
          });
          _streamingText = '';
          _isStreaming = false;
        });
      },
      cancelOnError: true,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final entriesAsync = ref.watch(logEntriesForDayProvider(todayDate));
    final catsAsync = ref.watch(categoriesProvider);
    final routineAsync = ref.watch(allRoutineSlotsProvider);
    final intentionAsync = ref.watch(todayIntentionProvider);

    String? contextPrompt;
    if (entriesAsync.hasValue &&
        catsAsync.hasValue &&
        routineAsync.hasValue &&
        intentionAsync.hasValue) {
      contextPrompt = _buildContextPrompt(
        entries: entriesAsync.value!,
        cats: catsAsync.value!,
        routine: routineAsync.value!,
        intention: intentionAsync.value,
      );
      if (!_contextLoaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _kickOff(contextPrompt!);
        });
      }
    }

    final intention = intentionAsync.valueOrNull;
    final verdict = intention?.verdictPositive;
    final accent = AppColors.accentForHour(today.hour);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'AI Debrief',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded, color: Colors.white),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── A5 Verdict strip ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: GlassCard(
                  borderRadius: 14,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Text(
                        'How was today?',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const Spacer(),
                      _VerdictButton(
                        icon: Icons.thumb_up_rounded,
                        active: verdict == true,
                        color: Colors.greenAccent,
                        onTap: () async {
                          await ref
                              .read(appDatabaseProvider)
                              .intentionsDao
                              .setVerdict(todayDate, verdict == true ? null : true);
                        },
                      ),
                      const SizedBox(width: 8),
                      _VerdictButton(
                        icon: Icons.thumb_down_rounded,
                        active: verdict == false,
                        color: Colors.redAccent,
                        onTap: () async {
                          await ref
                              .read(appDatabaseProvider)
                              .intentionsDao
                              .setVerdict(todayDate, verdict == false ? null : false);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // ── Chat messages ──────────────────────────────────────────
              Expanded(
                child: contextPrompt == null
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white54))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount:
                            _messages.length + (_isStreaming ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          // Streaming bubble at end
                          if (_isStreaming && i == _messages.length) {
                            return _MessageBubble(
                              role: 'assistant',
                              text: _streamingText.isEmpty
                                  ? '…'
                                  : _streamingText,
                              accent: accent,
                              isStreaming: true,
                            );
                          }
                          final msg = _messages[i];
                          // Hide the auto-generated opening user message
                          if (i == 0 && msg['role'] == 'user') {
                            return const SizedBox.shrink();
                          }
                          return _MessageBubble(
                            role: msg['role']!,
                            text: msg['content']!,
                            accent: accent,
                          );
                        },
                      ),
              ),
              // ── Input bar ──────────────────────────────────────────────
              _InputBar(
                controller: _controller,
                enabled: !_isStreaming && contextPrompt != null,
                accent: accent,
                onSend: (text) => _sendMessage(text, contextPrompt ?? ''),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Verdict toggle button ────────────────────────────────────────────────────

class _VerdictButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _VerdictButton({
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? color.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Icon(
          icon,
          color: active ? color : Colors.white30,
          size: 22,
        ),
      ),
    );
  }
}

// ── Chat message bubble ──────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final String role;
  final String text;
  final Color accent;
  final bool isStreaming;

  const _MessageBubble({
    required this.role,
    required this.text,
    required this.accent,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child:
                  Icon(Icons.auto_awesome_rounded, color: accent, size: 16),
            ),
          Flexible(
            child: GlassCard(
              borderRadius: 14,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              fillColor: isUser
                  ? accent.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.06),
              borderColor: isUser
                  ? accent.withValues(alpha: 0.40)
                  : Colors.white.withValues(alpha: 0.12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (isStreaming)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: _BlinkingCursor(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Blinking cursor for streaming ────────────────────────────────────────────

class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(width: 2, height: 14, color: Colors.white70),
    );
  }
}

// ── Input bar ────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final Color accent;
  final void Function(String) onSend;

  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.accent,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                style:
                    const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Ask a follow-up…',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: enabled ? onSend : null,
                textInputAction: TextInputAction.send,
                maxLines: null,
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.send_rounded,
                color: enabled ? accent : Colors.white30,
                size: 20,
              ),
              onPressed: enabled ? () => onSend(controller.text) : null,
            ),
          ],
        ),
      ),
    );
  }
}
