import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'notification_preferences.dart';

const _boxName = 'hikora_settings';
const _prefsKey = 'notification_preferences';

final notificationPreferencesProvider =
    StateNotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
  (ref) => NotificationPreferencesNotifier(),
);

class NotificationPreferencesNotifier extends StateNotifier<NotificationPreferences> {
  NotificationPreferencesNotifier() : super(NotificationPreferences.defaults) {
    _load();
  }

  Box<dynamic>? _box;

  Future<void> _load() async {
    try {
      _box ??= await Hive.openBox(_boxName);
      final raw = _box!.get(_prefsKey);
      if (raw is Map) {
        state = NotificationPreferences.fromJson(raw);
      }
    } catch (_) {
      state = NotificationPreferences.defaults;
    }
  }

  Future<void> _persist() async {
    try {
      _box ??= await Hive.openBox(_boxName);
      await _box!.put(_prefsKey, state.toJson());
    } catch (_) {}
  }

  Future<void> update(NotificationPreferences prefs) async {
    state = prefs;
    await _persist();
  }

  Future<void> setWeatherAlerts(bool v) =>
      update(state.copyWith(weatherAlerts: v));

  Future<void> setNewAchievements(bool v) =>
      update(state.copyWith(newAchievements: v));

  Future<void> setAiRecommendations(bool v) =>
      update(state.copyWith(aiRecommendations: v));

  Future<void> setTripRequests(bool v) =>
      update(state.copyWith(tripRequests: v));

  Future<void> setTripDecisions(bool v) =>
      update(state.copyWith(tripDecisions: v));

  Future<void> setTripChatMessages(bool v) =>
      update(state.copyWith(tripChatMessages: v));
}
