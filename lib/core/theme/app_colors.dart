import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Time-based background gradients ────────────────────────────────────
  // Dark bases — glass reads best on dark backgrounds
  static const _morning = [
    Color(0xFF3D1C0A), // deep burnt orange
    Color(0xFF7B3500), // amber-brown
    Color(0xFF4A1800), // dark sienna
  ];
  static const _midday = [
    Color(0xFF071428), // deep navy
    Color(0xFF0D2137), // ocean blue
    Color(0xFF0A2744), // slate blue
  ];
  static const _evening = [
    Color(0xFF1A0630), // deep violet
    Color(0xFF2D0B50), // dark purple
    Color(0xFF3D1A10), // ember
  ];
  static const _night = [
    Color(0xFF04060F), // near black
    Color(0xFF080D22), // deep indigo
    Color(0xFF060D1E), // midnight
  ];

  static List<Color> gradientForHour(int hour) {
    if (hour >= 5 && hour < 11) return _morning;
    if (hour >= 11 && hour < 17) return _midday;
    if (hour >= 17 && hour < 21) return _evening;
    return _night;
  }

  // Accent colour per time period — used on FABs and highlights
  static Color accentForHour(int hour) {
    if (hour >= 5 && hour < 11) return const Color(0xFFFF8A65); // warm orange
    if (hour >= 11 && hour < 17) return const Color(0xFF29B6F6); // sky blue
    if (hour >= 17 && hour < 21) return const Color(0xFFCE93D8); // lilac
    return const Color(0xFF7986CB); // soft indigo
  }

  // ── Category palette — 10 curated, colorblind-aware colours ───────────
  // Works at both full and low opacity for chart fills
  static const List<Color> palette = [
    Color(0xFF4E9AF1), // Blue       — Work
    Color(0xFF6BCB77), // Green      — Exercise
    Color(0xFF1A1040), // Deep Navy  — Sleep (dark; system)
    Color(0xFFFF6B6B), // Coral      — Entertainment
    Color(0xFFC77DFF), // Purple     — Social
    Color(0xFFFFD93D), // Yellow     — Learning
    Color(0xFFFF9F43), // Orange     — Meals
    Color(0xFF4ECDC4), // Teal       — Personal Care
    Color(0xFF74B9FF), // Light Blue — Travel
    Color(0xFF55EFC4), // Mint       — Admin
  ];

  static Color paletteAt(int index) => palette[index % palette.length];

  // ── Glass surface tokens ───────────────────────────────────────────────
  static const glassWhite = Color(0x1AFFFFFF); // 10 % white fill
  static const glassBorder = Color(0x33FFFFFF); // 20 % white border
  static const glassHighlight = Color(0x0DFFFFFF); // 5 % white (subtle)

  // ── Typography tokens ──────────────────────────────────────────────────
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xB3FFFFFF); // 70 %
  static const textMuted = Color(0x73FFFFFF); // 45 %
}
