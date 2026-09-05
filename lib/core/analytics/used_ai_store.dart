import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sticky "has this device ever used an AI feature?" flag.
///
/// Lives in SharedPreferences (no schema change, survives restarts). Flips true
/// on the first successful [GroqService] call and never resets. Reads are cached
/// in-memory so the analytics ping doesn't hit disk once it's known true.
class UsedAiStore {
  static const _key = 'used_ai';

  bool _cached = false;

  /// Whether AI has ever been used successfully on this device.
  Future<bool> value() async {
    if (_cached) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cached = prefs.getBool(_key) ?? false;
    } catch (e) {
      debugPrint('UsedAiStore.value: $e');
      return false;
    }
    return _cached;
  }

  /// Record that AI was used. Idempotent and best-effort — a failed write is
  /// swallowed so it never disrupts the AI call that triggered it.
  Future<void> markUsed() async {
    if (_cached) return;
    _cached = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (e) {
      debugPrint('UsedAiStore.markUsed: $e');
    }
  }
}

final usedAiStoreProvider = Provider<UsedAiStore>((ref) => UsedAiStore());
