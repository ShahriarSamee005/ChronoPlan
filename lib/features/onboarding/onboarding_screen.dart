import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/onboarding/seen_onboarding_store.dart';
import '../../core/theme/app_colors.dart';
import '../dashboard/widgets/time_gradient_background.dart';

/// One onboarding card. Copy is fixed — see [_cards].
class _Card {
  final IconData icon;
  final String title;
  final String body;
  const _Card({required this.icon, required this.title, required this.body});
}

const _cards = <_Card>[
  _Card(
    icon: Icons.history_rounded,
    title: 'Log the hour that just ended',
    body:
        'ChronoPlan works backwards. At 6:45, you log what you did between 5 '
        'and 6. No planning ahead, no guessing. Just what actually happened.',
  ),
  _Card(
    icon: Icons.block_rounded,
    title: "You can't log the future",
    body:
        'Only hours that have already passed. If you try to log ahead, the app '
        'will stop you. The current hour opens once it\'s underway.',
  ),
  _Card(
    icon: Icons.grid_view_rounded,
    title: 'Missing hours is normal',
    body:
        'You won\'t catch every hour, and that\'s fine. Open the logger and any '
        'hours you haven\'t filled in show up as quick picks. Fill them '
        'whenever you like — yesterday, this morning, three days ago.',
  ),
  _Card(
    icon: Icons.bedtime_rounded,
    title: "Tell it when you're asleep",
    body:
        'There\'s a switch at the top of the logger with a sun and a moon. Flip '
        'it to the moon when you go to bed, back to the sun when you wake. It '
        'fills in that whole stretch for you.',
  ),
  _Card(
    icon: Icons.mood_rounded,
    title: 'You decide how the day went',
    body:
        'Day View shows how close you got to your routine, in green, amber and '
        'red. That\'s just information. Whether it was a good day is your call, '
        'and yours only.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _cards.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Mark onboarding seen, then leave. Returns to wherever it was opened from
  /// when that's possible (replay from Profile), otherwise resets to home
  /// (first-run, where onboarding is the only route on the stack). `go`, never
  /// `push`, so first-run onboarding can't be popped back to.
  Future<void> _leave() async {
    await ref.read(seenOnboardingStoreProvider).markSeen();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentForHour(DateTime.now().hour);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TimeGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _cards.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _CardView(card: _cards[i], accent: accent),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Row(
                  children: [
                    _DotIndicator(count: _cards.length, index: _index, accent: accent),
                    const Spacer(),
                    _isLast
                        ? ElevatedButton(
                            onPressed: _leave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                            ),
                            child: const Text('Get started'),
                          )
                        : TextButton(
                            onPressed: _leave,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                            ),
                            child: const Text('Skip'),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── One card ──────────────────────────────────────────────────────────────────

class _CardView extends StatelessWidget {
  final _Card card;
  final Color accent;
  const _CardView({required this.card, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Icon(card.icon, color: accent, size: 30),
          ),
          const SizedBox(height: 28),
          Text(
            card.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            card.body,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dot indicator ─────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  final int count;
  final int index;
  final Color accent;
  const _DotIndicator({
    required this.count,
    required this.index,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          key: ValueKey('onboarding_dot_$i'),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(right: 6),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? accent : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
