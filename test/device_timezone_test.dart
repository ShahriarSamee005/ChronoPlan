import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:chronoplan/core/notifications/device_timezone.dart';

/// The fallback chain in resolveDeviceLocation(), driven at the platform
/// channel so the real code path runs end to end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_timezone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(tzdata.initializeTimeZones);

  void answerWith(Future<Object?> Function(MethodCall) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('uses the IANA name the platform reports', () async {
    answerWith((call) async {
      expect(call.method, 'getLocalTimezone');
      return 'Asia/Dhaka';
    });

    expect(await resolveDeviceLocation(), tz.getLocation('Asia/Dhaka'));
  });

  test('a reported zone the tz database lacks falls back to the current offset',
      () async {
    // getLocation() throws LocationNotFoundException for an unknown name;
    // resolveDeviceLocation must swallow it like any other failure.
    answerWith((_) async => 'Not/AZone');

    final resolved = await resolveDeviceLocation();

    expect(tz.TZDateTime.now(resolved).timeZoneOffset,
        DateTime.now().timeZoneOffset);
  });

  test('a platform failure falls back to the current offset, never throws',
      () async {
    answerWith((_) async => throw PlatformException(code: 'unavailable'));

    final resolved = await resolveDeviceLocation();

    expect(tz.TZDateTime.now(resolved).timeZoneOffset,
        DateTime.now().timeZoneOffset);
  });

  test('no channel at all (the headless-test case) still resolves', () async {
    messenger.setMockMethodCallHandler(channel, null);

    final resolved = await resolveDeviceLocation();

    expect(tz.TZDateTime.now(resolved).timeZoneOffset,
        DateTime.now().timeZoneOffset);
  });

  test('locationForCurrentOffset agrees with the device clock', () {
    final found = locationForCurrentOffset();

    expect(found, isNotNull);
    expect(tz.TZDateTime.now(found!).timeZoneOffset,
        DateTime.now().timeZoneOffset);
  });
}
