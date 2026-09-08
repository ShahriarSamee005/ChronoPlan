import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chronoplan/core/database/app_database.dart';
import 'package:chronoplan/features/log_entry/log_entry_sheet.dart';
import 'package:chronoplan/providers/database_provider.dart';

// The log entry sheet must open at, and never exceed, 85% of the screen height
// so a strip of screen stays visible above it and it never sits in Android's
// notification-shade gesture zone. The keyboard is the one allowed exception
// (handled by the root viewInsets padding, which sits OUTSIDE the cap) and is
// not exercised here — these tests open with no keyboard.
//
// Harness: in-memory Drift (11 default categories seeded on onCreate, all
// non-archived), the sheet opened through the real showModalBottomSheet with
// the exact args every call site uses, and a physical 1080x2400 @ dpr 3.0
// surface == 360 x 800 logical, a realistic phone where the full-category
// content is taller than 85% of the screen.

const double _physW = 1080.0;
const double _physH = 2400.0;
const double _dpr = 3.0;
const double _screenH = _physH / _dpr; // 800 logical

/// Logical screen height the sheet's `MediaQuery.size` sees, from the live view.
double _logicalScreenH(WidgetTester tester) {
  final view = tester.view;
  return view.physicalSize.height / view.devicePixelRatio;
}

Future<AppDatabase> _memoryDb(WidgetTester tester) => tester.runAsync(() async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.getSettings(); // force onCreate → seeds the 11 categories
      return db;
    }).then((v) => v!);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Let the Drift category/settings streams deliver, then paint.
Future<void> _flushStreams(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _openCreateSheet(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useRootNavigator: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const LogEntrySheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('open'));
  await tester.pump(); // push the route
  await tester.pump(const Duration(milliseconds: 400)); // animate in
  await _flushStreams(tester);
}

Future<void> _teardown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {});
  await tester.pump(const Duration(milliseconds: 16));
  await tester.runAsync(() => db.close());
}

final Finder _saveButton =
    find.widgetWithText(ElevatedButton, 'Save entry');

/// The Save button must sit fully inside the sheet's visible rect — not clipped
/// off the bottom — so it is on-screen and hittable without scrolling.
void _expectSaveWithinSheet(WidgetTester tester) {
  final sheet = tester.getRect(find.byType(LogEntrySheet));
  final save = tester.getRect(_saveButton);
  expect(
    save.bottom,
    lessThanOrEqualTo(sheet.bottom + 0.5),
    reason: 'Save bottom (${save.bottom}) must be within sheet bottom '
        '(${sheet.bottom}) — visible without scrolling',
  );
  expect(
    save.top,
    greaterThanOrEqualTo(sheet.top - 0.5),
    reason: 'Save top (${save.top}) must be within sheet top (${sheet.top})',
  );
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(_physW, _physH);
    view.devicePixelRatio = _dpr;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('Test A: full-content sheet never exceeds 85% of screen height',
      (tester) async {
    final db = await _memoryDb(tester);
    await _openCreateSheet(tester, db);

    expect(find.byType(LogEntrySheet), findsOneWidget);
    // Proves all 11 seeded categories rendered — i.e. content is at full height.
    expect(find.byType(FilterChip), findsNWidgets(11));

    final sheetH = tester.getSize(find.byType(LogEntrySheet)).height;
    final cap = _logicalScreenH(tester) * kLogSheetMaxHeightFraction;
    debugPrint('TEST A: sheetH=$sheetH cap=$cap screenH=$_screenH '
        'exceeds_by=${sheetH - cap}');

    expect(
      sheetH,
      lessThanOrEqualTo(cap + 0.5),
      reason: 'sheet ($sheetH) must not exceed 85% of screen ($cap)',
    );

    await _teardown(tester, db);
  });

  testWidgets('Test B: a short sheet stays short — the cap is a ceiling',
      (tester) async {
    // A tall screen: 85% of it comfortably exceeds even the minimal sheet's
    // content. The cap must not force the sheet to that 85% — a short sheet
    // must size to its content, proving the cap is a ceiling, not a fixed
    // height. (The default 800-logical surface is too short: the sheet's base
    // overhead alone is ~650px, within a whisker of its 680 cap.)
    tester.view.physicalSize = const Size(_physW, 3600.0); // 1200 logical @ dpr3
    tester.view.devicePixelRatio = _dpr;

    final db = await _memoryDb(tester);
    // Archive all but two categories so the content is genuinely short.
    await tester.runAsync(() async {
      final cats = await db.categoriesDao.getAll();
      for (final c in cats.skip(2)) {
        await db.categoriesDao.archive(c.id);
      }
    });
    await _openCreateSheet(tester, db);

    expect(find.byType(LogEntrySheet), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(2));

    final sheetH = tester.getSize(find.byType(LogEntrySheet)).height;
    final cap = _logicalScreenH(tester) * kLogSheetMaxHeightFraction; // 1020
    debugPrint('TEST B: sheetH=$sheetH cap=$cap '
        'screenH=${_logicalScreenH(tester)}');

    expect(
      sheetH,
      lessThan(cap),
      reason: 'a small sheet must size to content, well under the cap',
    );

    await _teardown(tester, db);
  });

  testWidgets('Test C: with tall content the Save button stays visible',
      (tester) async {
    // Default 360x800: full 11-category content (~800px) overflows the 680 cap,
    // so a Save button living inside the scroll area is pushed off-screen. Once
    // pinned below the scroll area it must stay visible with nothing scrolled.
    final db = await _memoryDb(tester);
    await _openCreateSheet(tester, db);

    expect(find.byType(FilterChip), findsNWidgets(11)); // content is at full height
    expect(_saveButton, findsOneWidget);

    final sheet = tester.getRect(find.byType(LogEntrySheet));
    final save = tester.getRect(_saveButton);
    debugPrint('TEST C: saveBottom=${save.bottom} sheetBottom=${sheet.bottom}');

    expect(
      save.bottom,
      lessThanOrEqualTo(sheet.bottom + 0.5),
      reason: 'Save must be visible within the sheet without scrolling',
    );

    await _teardown(tester, db);
  });

  testWidgets('Test D: Save is findable and hittable without scrolling',
      (tester) async {
    // Case 1 — overflow: short screen, tall content. Save is pinned, visible,
    // and a tap reaches it (saving the default past hour closes the sheet).
    {
      final db = await _memoryDb(tester);
      await _openCreateSheet(tester, db);

      expect(_saveButton, findsOneWidget);
      _expectSaveWithinSheet(tester);

      await tester.tap(_saveButton); // throws if not hittable
      await _flushStreams(tester);
      await tester.pump(const Duration(milliseconds: 400)); // sheet animates out
      expect(
        find.byType(LogEntrySheet),
        findsNothing,
        reason: 'tapping Save saved the entry and closed the sheet',
      );

      await _teardown(tester, db);
    }

    // Case 2 — content fits: a tall screen. Save is still pinned, visible, and
    // hittable without scrolling.
    {
      tester.view.physicalSize = const Size(_physW, 3600.0); // 1200 logical
      tester.view.devicePixelRatio = _dpr;
      final db = await _memoryDb(tester);
      await _openCreateSheet(tester, db);

      expect(_saveButton, findsOneWidget);
      _expectSaveWithinSheet(tester);

      await tester.tap(_saveButton);
      await _flushStreams(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LogEntrySheet), findsNothing);

      await _teardown(tester, db);
    }
  });
}
