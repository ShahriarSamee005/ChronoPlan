import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/theme/app_colors.dart';

void main() {
  group('Time-of-day accents', () {
    test('accentForHour returns expected values at boundary hours', () {
      // Morning band: 5–10
      expect(AppColors.accentForHour(5), const Color(0xFFFFF3EA));
      expect(AppColors.accentForHour(10), const Color(0xFFFFF3EA));
      // Midday band: 11–16
      expect(AppColors.accentForHour(11), const Color(0xFFFFF6E8));
      expect(AppColors.accentForHour(16), const Color(0xFFFFF6E8));
      // Evening band: 17–20
      expect(AppColors.accentForHour(17), const Color(0xFFEFF6FA));
      expect(AppColors.accentForHour(20), const Color(0xFFEFF6FA));
      // Night band: 21–4
      expect(AppColors.accentForHour(21), const Color(0xFFEDF0F7));
      expect(AppColors.accentForHour(4), const Color(0xFFEDF0F7));
    });

    // One representative hour per band.
    const bandHours = [8, 14, 18, 23];

    test('all four accents are pairwise distinct', () {
      final accents = bandHours.map(AppColors.accentForHour).toList();
      for (var i = 0; i < accents.length; i++) {
        for (var j = i + 1; j < accents.length; j++) {
          expect(accents[i], isNot(equals(accents[j])),
              reason: 'accents for hours ${bandHours[i]} and ${bandHours[j]} '
                  'must differ');
        }
      }
    });

    test('every accent is light (luminance > 0.8)', () {
      for (final h in bandHours) {
        expect(AppColors.accentForHour(h).computeLuminance(), greaterThan(0.8),
            reason: 'accent for hour $h must stay light');
      }
    });

    test('every onAccent is dark (luminance < 0.15)', () {
      for (final h in bandHours) {
        expect(
            AppColors.onAccentForHour(h).computeLuminance(), lessThan(0.15),
            reason: 'onAccent for hour $h must stay dark');
      }
    });

    test('accent vs onAccent are distinct with a luminance gap > 0.6', () {
      for (final h in bandHours) {
        final accent = AppColors.accentForHour(h);
        final onAccent = AppColors.onAccentForHour(h);
        expect(accent, isNot(equals(onAccent)),
            reason: 'accent and onAccent for hour $h must differ');
        final gap =
            (accent.computeLuminance() - onAccent.computeLuminance()).abs();
        expect(gap, greaterThan(0.6),
            reason: 'contrast for hour $h must stay high (gap was $gap)');
      }
    });

    test('sleepTrack is dark enough for a white thumb (luminance < 0.5)', () {
      expect(AppColors.sleepTrack.computeLuminance(), lessThan(0.5));
    });
  });
}
