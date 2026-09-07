import 'dart:async';

import 'package:flutter/material.dart';

/// A branded splash overlaid on top of [child] for the first moments after
/// launch. It sits ABOVE whatever the router built — it never decides what that
/// is, so the onboarding-vs-dashboard choice made in `main()` before `runApp`
/// is untouched. Once dismissed it removes itself from the tree entirely.
///
/// Frame one paints a solid `#BFD5F5` base — the same colour as the native
/// splash — so there is no visible jump from the OS splash to this one. The
/// gradient and the logo/wordmark then fade in on top of that base; after
/// [minimumVisible] the whole overlay fades out over [fadeOut] and is gone.
class SplashGate extends StatefulWidget {
  final Widget child;

  const SplashGate({super.key, required this.child});

  /// How long the splash stays fully present, measured from the first frame,
  /// before it begins fading out. Tests reference this instead of a literal.
  static const Duration minimumVisible = Duration(milliseconds: 1200);

  /// How long the whole overlay takes to fade out before it leaves the tree.
  static const Duration fadeOut = Duration(milliseconds: 350);

  /// How long the gradient + content take to fade in over the solid base.
  static const Duration _fadeIn = Duration(milliseconds: 400);

  /// Base / native-splash colour. Kept in sync with `flutter_native_splash.yaml`
  /// and the launcher icon background so the hand-off shows no jump.
  static const Color _baseColor = Color(0xFFBFD5F5);

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with TickerProviderStateMixin {
  late final AnimationController _fadeInController = AnimationController(
    vsync: this,
    duration: SplashGate._fadeIn,
  );

  late final AnimationController _fadeOutController = AnimationController(
    vsync: this,
    duration: SplashGate.fadeOut,
  );

  /// Whole-overlay opacity: 1 while shown, animating to 0 as it dismisses.
  late final Animation<double> _overlayOpacity = Tween<double>(
    begin: 1.0,
    end: 0.0,
  ).animate(CurvedAnimation(parent: _fadeOutController, curve: Curves.easeOut));

  /// Gradient + content fade-in over the solid base.
  late final Animation<double> _contentOpacity = CurvedAnimation(
    parent: _fadeInController,
    curve: Curves.easeOut,
  );

  Timer? _holdTimer;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _fadeInController.forward();

    // Hold from the first frame, then dismiss.
    _holdTimer = Timer(SplashGate.minimumVisible, () {
      if (!mounted) return;
      _fadeOutController.forward();
    });

    _fadeOutController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _removed = true);
      }
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _fadeInController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_removed)
          // Dismisses on a timer, so it must never swallow taps meant for the
          // child — IgnorePointer, not a gesture detector.
          IgnorePointer(
            key: const ValueKey('splash_overlay'),
            child: FadeTransition(
              opacity: _overlayOpacity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Solid base — matches the native splash, painted from frame one.
                  const ColoredBox(color: SplashGate._baseColor),
                  // Gradient + branded content fade in together over the base.
                  FadeTransition(
                    opacity: _contentOpacity,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: [0.0, 1.0],
                          colors: [Color(0xFFD3E2F8), Color(0xFF4883DE)],
                        ),
                      ),
                      child: Center(
                        // Single merged logo+wordmark. No colour filter — the
                        // wordmark is white by design.
                        child: Image.asset(
                          'assets/branding/splash.png',
                          key: const ValueKey('splash_content'),
                          width: 210,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
