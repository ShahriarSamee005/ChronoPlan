/// Quiet hours: no reminder fires from 01:00 through 08:59 on the user's own
/// clock. The 00:00 reminder still fires; the 09:00 reminder still fires.
///
/// Hard-coded by design for now — there is no user setting. Stated once here
/// so the window is testable.
const int kQuietStartHour = 1; // inclusive
const int kQuietEndHour = 9; // exclusive

/// Whether [hour] (0–23, wall clock) falls inside the quiet window.
bool isQuietHour(int hour) => hour >= kQuietStartHour && hour < kQuietEndHour;

/// Whether an alarm at [fireAt] would arrive during quiet hours, judged on the
/// DEVICE's wall clock.
///
/// Deliberately not `isQuietHour(fireAt.hour)`. A TZDateTime's `.hour` is the
/// hour in its own location, so this only agrees with the device clock when
/// `tz.local` IS the device zone. `NotificationService.init()` now installs it
/// via `initDeviceTimeZone()`, so in production the two normally coincide —
/// but `tz.local` still falls back to UTC when the platform lookup fails, and
/// a fireAt may be built in some other location entirely. Going through the
/// epoch yields the hour the user will actually see on their phone either way,
/// which is the thing the window is defined in terms of.
bool firesInQuietHours(DateTime fireAt) => isQuietHour(
      DateTime.fromMillisecondsSinceEpoch(fireAt.millisecondsSinceEpoch).hour,
    );
