import 'package:drift/drift.dart';

// Single-row table — seeded by AppDatabase.onCreate, never deleted.
class UserSettings extends Table {
  IntColumn get id => integer().autoIncrement()();

  // 'strict' | 'gentle'
  TextColumn get reminderMode =>
      text().withDefault(const Constant('gentle'))();
  // Used when reminderMode == 'strict'
  IntColumn get strictIntervalMinutes =>
      integer().withDefault(const Constant(60))();
  // JSON list of "HH:MM" strings used when reminderMode == 'gentle'
  TextColumn get gentleReminderTimes => text().withDefault(
        const Constant('["09:00","13:00","18:00","21:00"]'),
      )();

  BoolColumn get sleepModeActive =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get sleepModeStartedAt => dateTime().nullable()();
  // Date of last sleep-auto-detect prompt (prevents duplicate morning asks)
  DateTimeColumn get lastSleepPromptDate => dateTime().nullable()();

  // 'drill' | 'friendly' | 'neutral'
  TextColumn get aiPersona =>
      text().withDefault(const Constant('friendly'))();

  // Track app opens to time the usage-stats permission ask (after day 2+)
  IntColumn get appOpenCount =>
      integer().withDefault(const Constant(0))();
  BoolColumn get usageStatsPermissionAsked =>
      boolean().withDefault(const Constant(false))();

  // Date last morning intention prompt was shown (reset daily)
  DateTimeColumn get lastIntentionPromptDate => dateTime().nullable()();

  TextColumn get supabaseUserId => text().nullable()();
  TextColumn get lastSyncedAt => text().nullable()(); // ISO-8601
}
