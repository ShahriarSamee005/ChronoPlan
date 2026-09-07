import 'dart:async';

import 'package:chronoplan/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// The startup regression this guards: `main()` awaited the anonymous sign-in
/// before `runApp`, so a hung request blocked the first frame indefinitely.
/// [boundedSignIn] must always return — on a hang, on an error, and on success
/// — so `runApp` is always reached.
void main() {
  test('returns within the timeout when the sign-in call hangs', () async {
    // A future that never completes stands in for a hung network request.
    final hang = Completer<void>();
    addTearDown(() => hang.complete());

    await boundedSignIn(
      () => hang.future,
      timeout: const Duration(milliseconds: 50),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('boundedSignIn did not return on a hung call'),
    );
  });

  test('returns when the sign-in call throws', () async {
    await boundedSignIn(
      () => Future<void>.error(Exception('offline')),
      timeout: const Duration(seconds: 4),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('boundedSignIn did not return on a throwing call'),
    );
  });

  test('returns normally when the sign-in succeeds', () async {
    var called = false;
    await boundedSignIn(
      () async => called = true,
      timeout: const Duration(seconds: 4),
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('boundedSignIn did not return on success'),
    );
    expect(called, isTrue);
  });
}
