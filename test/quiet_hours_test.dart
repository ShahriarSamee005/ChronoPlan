import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:chronoplan/core/notifications/quiet_hours.dart';

void main() {
  tzdata.initializeTimeZones();

  group('isQuietHour', () {
    test('true for 01 through 08', () {
      for (var h = 1; h <= 8; h++) {
        expect(isQuietHour(h), isTrue, reason: 'hour $h is inside the window');
      }
    });

    test('false for 00 and for 09 through 23', () {
      expect(isQuietHour(0), isFalse, reason: 'the 00:00 reminder still fires');
      for (var h = 9; h <= 23; h++) {
        expect(isQuietHour(h), isFalse, reason: 'hour $h is outside the window');
      }
    });

    test('the window is stated once, by the two constants', () {
      expect(kQuietStartHour, 1);
      expect(kQuietEndHour, 9);
      expect(
        [for (var h = 0; h < 24; h++) if (isQuietHour(h)) h],
        [for (var h = kQuietStartHour; h < kQuietEndHour; h++) h],
      );
    });
  });

  group('firesInQuietHours judges the DEVICE clock, not the TZDateTime zone', () {
    // Each instant is built on the device clock, then re-expressed in
    // Pago Pago (UTC-11, no DST) — a zone whose `.hour` disagrees with the
    // device on every machine not itself at UTC-11. The expected answer comes
    // from the device-clock construction, so these hold on any machine.
    final far = tz.getLocation('Pacific/Pago_Pago');

    // One test below installs the device zone; keep that out of the others.
    tearDown(() => tz.setLocalLocation(tz.UTC));

    test('device-local noon is not quiet, whatever hour its zone reads', () {
      final noon = tz.TZDateTime.from(DateTime(2026, 9, 11, 12), far);
      expect(firesInQuietHours(noon), isFalse);
    });

    test('device-local 03:00 is quiet, whatever hour its zone reads', () {
      final three = tz.TZDateTime.from(DateTime(2026, 9, 11, 3), far);
      expect(firesInQuietHours(three), isTrue);
    });

    // The doc comment claims firesInQuietHours "stays correct if tz.local is
    // ever initialised to the device zone". That is now the production
    // configuration, so the claim is checked rather than trusted.
    test('claim check: with tz.local AS the device zone, it agrees with '
        'isQuietHour on every hour', () {
      final offset = DateTime.now().timeZoneOffset;
      final deviceZone = tz.timeZoneDatabase.locations.values
          .firstWhere((l) => tz.TZDateTime.now(l).timeZoneOffset == offset);
      tz.setLocalLocation(deviceZone);

      for (var h = 0; h < 24; h++) {
        final fire = tz.TZDateTime(tz.local, 2026, 9, 11, h, 0);
        expect(firesInQuietHours(fire), isQuietHour(h),
            reason: 'hour $h: epoch route and .hour must now coincide');
        expect(firesInQuietHours(fire), isQuietHour(fire.hour));
      }
    });

    test('boundaries on the device clock: 00:59 and 09:00 fire, 01:00 and '
        '08:59 do not', () {
      bool q(int h, int m) =>
          firesInQuietHours(tz.TZDateTime.from(DateTime(2026, 9, 11, h, m), far));
      expect(q(0, 59), isFalse);
      expect(q(1, 0), isTrue);
      expect(q(8, 59), isTrue);
      expect(q(9, 0), isFalse);
    });
  });
}
