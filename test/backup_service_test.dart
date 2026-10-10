import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:chronoplan/core/backup/backup_serializer.dart';
import 'package:chronoplan/core/backup/backup_service.dart';
import 'package:chronoplan/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

/// Covers the file-write half of BackupService without a device or the share
/// sheet: exportToFile is given a real temp dir (its test-only seam) so no
/// path_provider platform channel is needed. The share sheet itself
/// (shareXFiles) is platform UI and is left to device verification.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open(r'C:\Python314\DLLs\sqlite3.dll'),
  );

  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('chronoplan_backup_test');
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('exportToFile writes a JSON file that decodes to the backup map',
      () async {
    final path = await BackupService(db).exportToFile(directory: tmp);

    final file = File(path);
    expect(file.existsSync(), isTrue);
    expect(fileBasename(path), matches(r'^chronoplan_backup_\d{8}_\d{6}\.json$'));

    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], db.schemaVersion);
    expect((decoded['tables'] as Map).keys.toSet(), {
      kTableCategories,
      kTableLogEntries,
      kTableRoutineSlots,
      kTableDailyIntentions,
      kTableUserSettings,
      kTableDismissedSuggestions,
      kTableDismissedCarves,
      kTableIntentionTasks,
    });
    // package_info_plus absent → appVersion omitted.
    expect(decoded.containsKey('appVersion'), isFalse);
  });

  test('exported file reflects real seeded rows', () async {
    await db.categoriesDao.insertCategory(
      CategoriesCompanion.insert(name: 'Focus', colorValue: 0xFF112233),
    );

    final path = await BackupService(db).exportToFile(directory: tmp);
    final decoded =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final cats = ((decoded['tables'] as Map)[kTableCategories] as List).cast<Map>();

    expect(cats.any((c) => c['name'] == 'Focus'), isTrue);
  });
}

/// Tiny basename helper to avoid importing path just for the assertion.
String fileBasename(String path) => path.split(RegExp(r'[/\\]')).last;
