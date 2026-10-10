/// Pure, dependency-free serialization for the local "export my data" feature
/// (Backup/restore Phase 1). NO cloud, NO network, NO schema change: this file
/// only turns already-loaded Drift rows into one JSON-able [Map].
///
/// The map is the on-disk shape of an exported `.json` file:
///   * `schemaVersion` — the Drift `AppDatabase.schemaVersion` at export time,
///     passed in by the caller so this stays pure and never drifts from the DB.
///   * `exportedAt` — ISO-8601 UTC timestamp of the export.
///   * `appVersion` — the app's version string, present only when the caller
///     supplies one (e.g. from `package_info`); omitted entirely otherwise.
///   * `tables` — one entry per Drift table, keyed by its SQL table name, each
///     a `List` of that table's rows via Drift's generated `toJson()`.
///
/// Keeping this a pure function (rows in → map out) makes it trivially testable
/// with hand-built row objects and no database at all.
library;

import 'package:drift/drift.dart' show ValueSerializer;

import '../database/app_database.dart';

/// Serializer pinned for backups. `serializeDateTimeValuesAsString: false`
/// forces every `DateTime` column to a unix timestamp — milliseconds since
/// epoch, a plain JSON `int` — which round-trips losslessly at millisecond
/// precision via `DateTime.fromMillisecondsSinceEpoch`. We pin it rather than
/// trust the global `driftRuntimeOptions.defaultSerializer` so the on-disk
/// format is stable and deterministic regardless of any ambient serializer
/// change elsewhere in the app. (Drift's deserializer accepts both int and
/// string forms, so Phase 6 restore stays tolerant, but we emit exactly one.)
const ValueSerializer _backupSerializer =
    ValueSerializer.defaults(serializeDateTimeValuesAsString: false);

/// SQL table names used as keys under `tables`. These match the Drift table
/// definitions and are the stable contract an importer keys off — do not rename
/// without a matching importer change.
const String kTableCategories = 'categories';
const String kTableLogEntries = 'log_entries';
const String kTableRoutineSlots = 'routine_slots';
const String kTableDailyIntentions = 'daily_intentions';
const String kTableUserSettings = 'user_settings';
const String kTableDismissedSuggestions = 'dismissed_suggestions';
const String kTableDismissedCarves = 'dismissed_carves';
const String kTableIntentionTasks = 'intention_tasks';

/// Immutable transport holder for the full set of rows read from the database
/// for a backup. Produced by `AppDatabase.readAllForBackup()` and handed to
/// [buildBackupMap]; keeps the read layer and the serializer decoupled.
class BackupData {
  final List<Category> categories;
  final List<LogEntry> logEntries;
  final List<RoutineSlot> routineSlots;
  final List<DailyIntention> dailyIntentions;
  final List<UserSetting> userSettings;
  final List<DismissedSuggestion> dismissedSuggestions;
  final List<DismissedCarve> dismissedCarves;
  final List<IntentionTask> intentionTasks;

  const BackupData({
    required this.categories,
    required this.logEntries,
    required this.routineSlots,
    required this.dailyIntentions,
    required this.userSettings,
    required this.dismissedSuggestions,
    required this.dismissedCarves,
    required this.intentionTasks,
  });
}

/// Builds one JSON-able map holding every table's rows plus backup metadata.
///
/// [schemaVersion] should be the live `AppDatabase.schemaVersion` (the caller
/// has the db; passing it in keeps this function pure and free of a DB import
/// for the value). [exportedAt] defaults to the current UTC time. [appVersion],
/// when non-null, is emitted as an `appVersion` key; when null the key is
/// omitted entirely (matches "from package_info if available, else omit").
///
/// The returned map contains only JSON-primitive values (via Drift's generated
/// `toJson()` on each row), so `jsonEncode(...)` on the result always succeeds.
Map<String, dynamic> buildBackupMap({
  required List<Category> categories,
  required List<LogEntry> logEntries,
  required List<RoutineSlot> routineSlots,
  required List<DailyIntention> dailyIntentions,
  required List<UserSetting> userSettings,
  required List<DismissedSuggestion> dismissedSuggestions,
  required List<DismissedCarve> dismissedCarves,
  required List<IntentionTask> intentionTasks,
  required int schemaVersion,
  DateTime? exportedAt,
  String? appVersion,
}) {
  final when = (exportedAt ?? DateTime.now()).toUtc();
  return <String, dynamic>{
    'schemaVersion': schemaVersion,
    'exportedAt': when.toIso8601String(),
    // Omit the key entirely when no version is available.
    if (appVersion != null) 'appVersion': appVersion,
    'tables': <String, dynamic>{
      kTableCategories: [
        for (final r in categories) r.toJson(serializer: _backupSerializer)
      ],
      kTableLogEntries: [
        for (final r in logEntries) r.toJson(serializer: _backupSerializer)
      ],
      kTableRoutineSlots: [
        for (final r in routineSlots) r.toJson(serializer: _backupSerializer)
      ],
      kTableDailyIntentions: [
        for (final r in dailyIntentions) r.toJson(serializer: _backupSerializer)
      ],
      kTableUserSettings: [
        for (final r in userSettings) r.toJson(serializer: _backupSerializer)
      ],
      kTableDismissedSuggestions: [
        for (final r in dismissedSuggestions)
          r.toJson(serializer: _backupSerializer)
      ],
      kTableDismissedCarves: [
        for (final r in dismissedCarves) r.toJson(serializer: _backupSerializer)
      ],
      kTableIntentionTasks: [
        for (final r in intentionTasks) r.toJson(serializer: _backupSerializer)
      ],
    },
  };
}

/// Convenience wrapper: builds the backup map from a [BackupData] holder.
Map<String, dynamic> buildBackupMapFrom(
  BackupData data, {
  required int schemaVersion,
  DateTime? exportedAt,
  String? appVersion,
}) =>
    buildBackupMap(
      categories: data.categories,
      logEntries: data.logEntries,
      routineSlots: data.routineSlots,
      dailyIntentions: data.dailyIntentions,
      userSettings: data.userSettings,
      dismissedSuggestions: data.dismissedSuggestions,
      dismissedCarves: data.dismissedCarves,
      intentionTasks: data.intentionTasks,
      schemaVersion: schemaVersion,
      exportedAt: exportedAt,
      appVersion: appVersion,
    );
