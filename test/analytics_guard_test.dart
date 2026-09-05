import 'package:chronoplan/core/analytics/analytics_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldPing', () {
    test('null lastPing → true (never pinged before)', () {
      expect(
        shouldPing(lastPing: null, now: DateTime(2026, 9, 5, 10, 0)),
        isTrue,
      );
    });

    test('lastPing yesterday → true', () {
      expect(
        shouldPing(
          lastPing: DateTime(2026, 9, 4, 10, 0),
          now: DateTime(2026, 9, 5, 10, 0),
        ),
        isTrue,
      );
    });

    test('lastPing earlier today → false', () {
      expect(
        shouldPing(
          lastPing: DateTime(2026, 9, 5, 8, 0),
          now: DateTime(2026, 9, 5, 20, 0),
        ),
        isFalse,
      );
    });

    test(
      'same clock time yesterday (~23h ago) → true — proves the guard compares '
      'calendar days, not elapsed hours',
      () {
        // 23h separates these, which is < 24h, yet they are different calendar
        // days: an elapsed-hours guard would (wrongly) say false.
        expect(
          shouldPing(
            lastPing: DateTime(2026, 9, 4, 11, 0),
            now: DateTime(2026, 9, 5, 10, 0),
          ),
          isTrue,
        );
      },
    );

    test(
      'lastPing 1h ago but across midnight → true — same calendar-day rule, '
      'the other direction (small elapsed gap still crosses the day boundary)',
      () {
        expect(
          shouldPing(
            lastPing: DateTime(2026, 9, 4, 23, 30),
            now: DateTime(2026, 9, 5, 0, 30),
          ),
          isTrue,
        );
      },
    );
  });
}
