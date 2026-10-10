import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/database_provider.dart';
import '../database/app_database.dart';
import 'backup_serializer.dart';

/// Thrown when an export fails. Carries a user-facing [message] so the UI can
/// surface it directly (snackbar) instead of leaking a raw exception/stack.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => 'BackupException: $message';
}

/// Local "export my data" (Backup/restore Phase 1). 100% local: reads the DB,
/// serializes to one JSON file in the cache dir, and offers it to the platform
/// share sheet. NO cloud, NO network, NO account, NO secrets.
///
/// No `package_info_plus` in the project, so [appVersion] is null and the
/// serializer omits the `appVersion` key.
class BackupService {
  final AppDatabase _db;

  BackupService(this._db);

  static final DateFormat _stamp = DateFormat('yyyyMMdd_HHmmss');

  /// Reads every table, builds the backup map, and writes it as a pretty JSON
  /// file into the temporary/cache directory. Returns the absolute file path.
  ///
  /// [directory] is a test-only seam: when null (production) the file goes to
  /// the platform cache dir via `path_provider`; tests pass a real temp dir so
  /// the write path is exercised without a device/plugin channel.
  ///
  /// Any failure is caught and rethrown as a [BackupException] with a clear
  /// message — never an uncaught crash.
  Future<String> exportToFile({Directory? directory}) async {
    try {
      final data = await _db.readAllForBackup();
      final map = buildBackupMapFrom(
        data,
        schemaVersion: _db.schemaVersion,
        // package_info_plus is not a dependency in this phase → omit the key.
        appVersion: null,
      );
      final json = const JsonEncoder.withIndent('  ').convert(map);

      final dir = directory ?? await getTemporaryDirectory();
      final fileName = 'chronoplan_backup_${_stamp.format(DateTime.now())}.json';
      final file = File(p.join(dir.path, fileName));
      await file.writeAsString(json, flush: true);
      return file.path;
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException("Couldn't create your backup file. ($e)");
    }
  }

  /// Opens the platform share sheet on an already-written backup [path] so the
  /// user can save it to Drive, email it, etc. Split from [exportToFile] so a
  /// caller can dismiss its progress UI before the share sheet appears.
  Future<void> shareFile(String path) async {
    try {
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/json')],
        subject: 'ChronoPlan backup',
        text: 'ChronoPlan data export',
      );
    } catch (e) {
      throw BackupException("Couldn't open the share sheet. ($e)");
    }
  }

  /// Convenience: write the file then immediately share it.
  Future<void> exportAndShare() async {
    final path = await exportToFile();
    await shareFile(path);
  }
}

/// App-lifetime provider, mirroring `analyticsServiceProvider`.
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.read(appDatabaseProvider));
});
