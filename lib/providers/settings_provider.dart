import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ai/groq_service.dart';
import '../core/analytics/used_ai_store.dart';
import '../core/database/app_database.dart';
import 'database_provider.dart';

// ── Settings stream ────────────────────────────────────────────────────────

final settingsProvider = StreamProvider<UserSetting>((ref) {
  return ref.watch(appDatabaseProvider).watchSettings();
});

// ── AI service ─────────────────────────────────────────────────────────────

final aiServiceProvider = Provider<GroqService>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  return GroqService(
    persona: settings?.aiPersona ?? 'friendly',
    usedAiStore: ref.read(usedAiStoreProvider),
  );
});

// ── Notifier for patching UserSettings ────────────────────────────────────

class SettingsNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AppDatabase get _db => ref.read(appDatabaseProvider);

  Future<void> setReminderMode(String mode) =>
      _db.updateSettings(UserSettingsCompanion(
        reminderMode: Value(mode),
      ));

  Future<void> setCustomInterval(int minutes) =>
      _db.updateSettings(UserSettingsCompanion(
        strictIntervalMinutes: Value(minutes),
      ));

  Future<void> setAiPersona(String persona) =>
      _db.updateSettings(UserSettingsCompanion(
        aiPersona: Value(persona),
      ));

  Future<void> setSleepMode({required bool active}) async {
    if (!active) {
      final current = await _db.getSettings();
      if (current.sleepModeStartedAt != null) {
        final sleepCat = await _db.categoriesDao.findByName('Sleep');
        await _db.logEntriesDao.insertRetroactive(
          startTime: current.sleepModeStartedAt!,
          endTime: DateTime.now(),
          categoryId: sleepCat?.id,
          description: 'Sleep',
        );
      }
    }
    await _db.updateSettings(UserSettingsCompanion(
      sleepModeActive: Value(active),
      sleepModeStartedAt: Value(active ? DateTime.now() : null),
    ));
  }

  Future<void> incrementAppOpenCount() async {
    final current = await _db.getSettings();
    await _db.updateSettings(UserSettingsCompanion(
      appOpenCount: Value(current.appOpenCount + 1),
    ));
  }

  Future<void> dismissUsageStatsCard() =>
      _db.updateSettings(UserSettingsCompanion(
        usageStatsPermissionAsked: const Value(true),
      ));
}

final settingsNotifierProvider =
    AsyncNotifierProvider<SettingsNotifier, void>(SettingsNotifier.new);
