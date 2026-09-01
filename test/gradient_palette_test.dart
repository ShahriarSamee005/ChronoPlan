import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/theme/app_colors.dart';

void main() {
  group('Time-of-day gradient palettes', () {
    test('gradientForHour maps representative hours correctly', () {
      final morning = AppColors.gradientForHour(8);
      final midday = AppColors.gradientForHour(14);
      final evening = AppColors.gradientForHour(18);
      final night = AppColors.gradientForHour(23);

      expect(morning, isA<List<Color>>());
      expect(midday, isA<List<Color>>());
      expect(evening, isA<List<Color>>());
      expect(night, isA<List<Color>>());
    });

    test('each palette contains exactly 3 colors', () {
      expect(AppColors.gradientForHour(8).length, 3);
      expect(AppColors.gradientForHour(14).length, 3);
      expect(AppColors.gradientForHour(18).length, 3);
      expect(AppColors.gradientForHour(23).length, 3);
    });

    test('all four palettes are pairwise distinct', () {
      final morning = AppColors.gradientForHour(8);
      final midday = AppColors.gradientForHour(14);
      final evening = AppColors.gradientForHour(18);
      final night = AppColors.gradientForHour(23);

      final palettes = [morning, midday, evening, night];
      final labels = ['morning', 'midday', 'evening', 'night'];

      for (var i = 0; i < palettes.length; i++) {
        for (var j = i + 1; j < palettes.length; j++) {
          expect(
            palettes[i],
            isNot(equals(palettes[j])),
            reason: '${labels[i]} and ${labels[j]} must be different palettes',
          );
        }
      }
    });
  });
}
