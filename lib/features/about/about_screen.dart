import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/glass_card.dart';
import '../dashboard/widgets/time_gradient_background.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          'About',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ),
      body: TimeGradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
            children: [
              // App name + icon
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.accentForHour(DateTime.now().hour)
                            .withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.accentForHour(DateTime.now().hour)
                              .withValues(alpha: 0.50),
                        ),
                      ),
                      child: Icon(
                        Icons.schedule_rounded,
                        color: AppColors.accentForHour(DateTime.now().hour),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ChronoPlan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Version 1.0.0',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              GlassCard(
                opacity: 0.10,
                padding: const EdgeInsets.all(20),
                child: const Text(
                  'ChronoPlan helps you understand where your hours actually go. '
                  'Log your time hour by hour, build a routine, compare plans against reality, '
                  'and let AI help you reflect on your days.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GlassCard(
                opacity: 0.10,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'CREDITS',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Built with Flutter, Drift, Riverpod, and Claude AI.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Typography: Manrope by Mikhail Sharanda.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
