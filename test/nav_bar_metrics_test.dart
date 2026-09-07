import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chronoplan/features/shell/app_shell.dart';

/// Resolves `NavBarMetrics.clearance` against a real context whose bottom
/// safe-area inset is [inset].
Future<double> _clearanceAt(WidgetTester tester, double inset) async {
  late double result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(padding: EdgeInsets.only(bottom: inset)),
      child: Builder(
        builder: (context) {
          result = NavBarMetrics.clearance(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  group('NavBarMetrics', () {
    testWidgets(
      'clearance leaves real breathing room above the pill '
      '(> height + bottomMargin) with no safe-area inset',
      (tester) async {
        final clearance = await _clearanceAt(tester, 0);
        expect(
          clearance,
          greaterThan(NavBarMetrics.height + NavBarMetrics.bottomMargin),
          reason: 'the last scroll row must clear the pill with room to spare',
        );
      },
    );

    testWidgets(
      'clearance grows by exactly the safe-area inset',
      (tester) async {
        final base = await _clearanceAt(tester, 0);
        final at24 = await _clearanceAt(tester, 24);
        final at48 = await _clearanceAt(tester, 48);

        expect(at24 - base, 24);
        expect(at48 - base, 48);
      },
    );

    test('radius * 2 == height — the pill stays fully rounded', () {
      expect(NavBarMetrics.radius * 2, NavBarMetrics.height);
    });
  });

  testWidgets(
    'AppShell renders a rounded (ClipRRect) floating pill with all four labels',
    (tester) async {
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (context, state, child) => AppShell(child: child),
            routes: [
              GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      // The pill clips with a ClipRRect now, not the old bare ClipRect.
      expect(find.byType(ClipRRect), findsWidgets);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Routine'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
    },
  );
}
