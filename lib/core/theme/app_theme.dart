import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark();
    final manrope = GoogleFonts.manropeTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4E9AF1),
        secondary: Color(0xFF6BCB77),
        surface: Color(0xFF080D22),
        error: Color(0xFFFF6B6B),
      ),
      textTheme: manrope.copyWith(
        displayLarge: GoogleFonts.manrope(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 32,
        ),
        titleLarge: GoogleFonts.manrope(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 20,
        ),
        titleMedium: GoogleFonts.manrope(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: GoogleFonts.manrope(
          color: AppColors.textSecondary,
          fontSize: 16,
        ),
        bodyMedium: GoogleFonts.manrope(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        labelSmall: GoogleFonts.manrope(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFF4E9AF1),
            width: 1.5,
          ),
        ),
        hintStyle: GoogleFonts.manrope(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
        labelStyle: GoogleFonts.manrope(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4E9AF1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 14,
          ),
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          elevation: 0,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.glassWhite,
        selectedColor:
            const Color(0xFF4E9AF1).withValues(alpha: 0.25),
        disabledColor: AppColors.glassHighlight,
        side: const BorderSide(color: AppColors.glassBorder),
        labelStyle: GoogleFonts.manrope(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 4,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF4E9AF1),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: StadiumBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.glassBorder,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor:
            WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF4E9AF1);
          }
          return AppColors.textMuted;
        }),
        trackColor:
            WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF4E9AF1).withValues(alpha: 0.3);
          }
          return AppColors.glassWhite;
        }),
      ),
    );
  }
}
