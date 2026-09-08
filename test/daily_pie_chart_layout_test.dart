import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/dashboard/widgets/daily_pie_chart_card.dart';
import 'package:chronoplan/providers/categories_provider.dart';
import 'package:chronoplan/providers/log_entries_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Category _cat(int id, String name) => Category(
      id: id,
      name: name,
      colorValue: 0xFF4E9AF1,
      isArchived: false,
      isSystem: false,
      createdAt: DateTime(2026, 1, 1),
    );

LogEntry _entry(int id, int categoryId, int minutes) {
  final start = DateTime(2026, 9, 8, 8, 0);
  return LogEntry(
    id: id,
    description: 'entry $id',
    categoryId: categoryId,
    startTime: start,
    endTime: start.add(Duration(minutes: minutes)),
    isRealTime: true,
    isAiParsed: false,
    isUsageDerived: false,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // ── Test A — radius maths (pure unit) ─────────────────────────────────────
  group('pieRadiusFor', () {
    test('pie + touch growth fits inside the chart slot', () {
      for (final width in <double>[120, 165, 200, 320]) {
        final radius = pieRadiusFor(width);
        // The donut's outer edge in the touched state must stay within the
        // slot's half-width: centerSpace + radius + touchGrowth <= width / 2.
        expect(
          kPieCenterSpace + radius + kPieTouchGrowth,
          lessThanOrEqualTo(width / 2),
          reason: 'chartWidth=$width radius=$radius overspills its slot',
        );
      }
    });

    test('radius never drops below the floor on a very narrow slot', () {
      // 60px cannot physically hold the donut; the function must clamp, not
      // return a negative radius.
      expect(pieRadiusFor(60), greaterThanOrEqualTo(kPieRadiusFloor));
      expect(pieRadiusFor(60), kPieRadiusFloor);
    });

    test('radius never exceeds the ceiling on a very wide slot', () {
      expect(pieRadiusFor(2000), lessThanOrEqualTo(kPieRadiusCeiling));
    });
  });

  // ── Test B — no overflow with many categories (widget) ────────────────────
  testWidgets('no overflow with 11 logged categories at phone width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 11 categories, each with logged time today — a default install's count.
    final cats = <Category>[
      for (var i = 1; i <= 11; i++) _cat(i, 'Category number $i'),
    ];
    final entries = <LogEntry>[
      for (var i = 1; i <= 11; i++) _entry(i, i, (12 - i) * 15),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayEntriesProvider.overrideWith((ref) => Stream.value(entries)),
          categoriesProvider.overrideWith((ref) => Stream.value(cats)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: const [DailyPieChartCard()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
