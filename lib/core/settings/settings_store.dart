import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

class SettingsStore extends ValueNotifier<AppSettings> {
  SettingsStore._(this._preferences, AppSettings value) : super(value);

  static const _storageKey = 'dev_orbit.settings.v1';
  final SharedPreferences _preferences;

  static Future<SettingsStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      return SettingsStore._(preferences, AppSettings.defaults());
    }
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      return SettingsStore._(preferences, AppSettings.fromJson(json));
    } catch (_) {
      return SettingsStore._(preferences, AppSettings.defaults());
    }
  }

  Future<void> update(AppSettings settings) async {
    value = settings;
    await _preferences.setString(_storageKey, jsonEncode(settings.toJson()));
  }
}
