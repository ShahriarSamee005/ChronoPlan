import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Full-screen gradient that smoothly transitions when the hour changes.
class TimeGradientBackground extends StatefulWidget {
  final Widget child;

  const TimeGradientBackground({super.key, required this.child});

  @override
  State<TimeGradientBackground> createState() =>
      _TimeGradientBackgroundState();
}

class _TimeGradientBackgroundState
    extends State<TimeGradientBackground> {
  late List<Color> _colors;
  Timer? _hourTimer;

  @override
  void initState() {
    super.initState();
    _colors = AppColors.gradientForHour(DateTime.now().hour);
    _scheduleNextHour();
  }

  void _scheduleNextHour() {
    final now = DateTime.now();
    // Fire exactly at the start of the next hour
    final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
    final delay = nextHour.difference(now);

    _hourTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _colors = AppColors.gradientForHour(DateTime.now().hour));
      _scheduleNextHour(); // re-arm for the hour after that
    });
  }

  @override
  void dispose() {
    _hourTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(seconds: 3),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _colors,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: widget.child,
    );
  }
}
