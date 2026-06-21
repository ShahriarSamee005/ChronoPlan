import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/ai/claude_service.dart';
import '../core/database/app_database.dart';

import 'database_provider.dart';

const _kClaudeKeyField = 'claude_api_key';
const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

// ── Settings stream ────────────────────────────────────────────────────────

final settingsProvider = StreamProvider<UserSetting>((ref) {
  return ref.watch(appDatabaseProvider).watchSettings();
});

// ── API key (stored in secure storage, not the DB) ─────────────────────────

final claudeApiKeyProvider = FutureProvider<String?>((ref) async {
  return _secureStorage.read(key: _kClaudeKeyField);
});

// ── ClaudeService (null when no key is set or key is empty) ───────────────

final claudeServiceProvider = Provider<ClaudeService?>((ref) {
  final keyAsync = ref.watch(claudeApiKeyProvider);
  final settingsAsync = ref.watch(settingsProvider);

  return keyAsync.whenOrNull(
    data: (key) {
      if (key == null || key.isEmpty) return null;
      final persona = settingsAsync.valueOrNull?.aiPersona ?? 'friendly';
      return ClaudeService(apiKey: key, persona: persona);
    },
  );
});

// ── Notifier for saving / clearing the API key ────────────────────────────

class ApiKeyNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> saveKey(String key) async {
    await _secureStorage.write(key: _kClaudeKeyField, value: key.trim());
    ref.invalidate(claudeApiKeyProvider);
  }

  Future<void> clearKey() async {
    await _secureStorage.delete(key: _kClaudeKeyField);
    ref.invalidate(claudeApiKeyProvider);
  }
}

final apiKeyNotifierProvider =
    AsyncNotifierProvider<ApiKeyNotifier, void>(ApiKeyNotifier.new);

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
      // Wake: insert a retroactive Sleep entry covering the sleep window
      final current = await _db.getSettings();
      if (current.sleepModeStartedAt != null) {
        final sleepCat =
            await _db.categoriesDao.findByName('Sleep');
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
}

final settingsNotifierProvider =
    AsyncNotifierProvider<SettingsNotifier, void>(SettingsNotifier.new);
