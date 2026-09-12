import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

/// Resolves the device's IANA zone and installs it as [tz.local].
///
/// Until this runs, `tz.local` is UTC. Everything scheduled through
/// `tz.TZDateTime(tz.local, ...)` is therefore built on a UTC wall clock, so a
/// "Sunday 20:00" alarm fires at Sunday 20:00 UTC — Monday 02:00 for a UTC+6
/// user. [quiet_hours.dart]'s `firesInQuietHours` works around that for
/// reminders by going through the epoch; the weekly reflection had no such
/// workaround and landed in the middle of the night.
///
/// Called once from `NotificationService.init()`, before anything is
/// scheduled.
Future<void> initDeviceTimeZone() async {
  tz.setLocalLocation(await resolveDeviceLocation());
}

/// The device's tz location, with two fallbacks.
///
/// 1. The platform's IANA name via flutter_timezone — correct across DST,
///    since the zone carries its own transition rules.
/// 2. Failing that (no platform channel in tests, or a name the bundled tz
///    database does not carry), any zone currently at the device's UTC offset.
///    Right now, but not necessarily across a DST transition — an acceptable
///    degradation, and exact for the fixed-offset zones where it usually bites.
/// 3. Failing that, [tz.UTC] — the pre-existing behaviour, so a failure here
///    can never be worse than not calling this at all.
@visibleForTesting
Future<tz.Location> resolveDeviceLocation() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    return tz.getLocation(info.identifier);
  } catch (_) {
    return locationForCurrentOffset() ?? tz.UTC;
  }
}

/// Any tz location whose offset right now equals the device's, or null.
@visibleForTesting
tz.Location? locationForCurrentOffset() {
  final offset = DateTime.now().timeZoneOffset;
  for (final location in tz.timeZoneDatabase.locations.values) {
    if (tz.TZDateTime.now(location).timeZoneOffset == offset) return location;
  }
  return null;
}
