import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Glassmorphism surface card.
///
/// Wraps [child] in a [BackdropFilter] blur + semi-transparent fill +
/// 1 px light border.  Reduce [blurSigma] on lower-end devices if
/// frame drops occur (test early — see spec note on performance).
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double opacity;
  final double blurSigma;
  final EdgeInsets? padding;
  final Color? borderColor;
  final Color? fillColor;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.opacity = 0.12,
    this.blurSigma = 10,
    this.padding,
    this.borderColor,
    this.fillColor,
    this.onTap,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: fillColor ??
                  Colors.white.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? AppColors.glassBorder,
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
