import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../desktop/desktop_clipboard_diagnostics.dart';
import 'app_settings.dart';

class SettingsStore extends ValueNotifier<AppSettings> {
  SettingsStore._(this._preferences, AppSettings value) : super(value);

  static const _storageKey = 'dev_orbit.settings.v1';
  final SharedPreferences _preferences;

  static Future<SettingsStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      final store = SettingsStore._(preferences, AppSettings.defaults());
      DesktopClipboardDiagnostics.configure(store.value.clipboardTraceEnabled);
      return store;
    }
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final store = SettingsStore._(preferences, AppSettings.fromJson(json));
      DesktopClipboardDiagnostics.configure(store.value.clipboardTraceEnabled);
      return store;
    } catch (_) {
      final store = SettingsStore._(preferences, AppSettings.defaults());
      DesktopClipboardDiagnostics.configure(store.value.clipboardTraceEnabled);
      return store;
    }
  }

  Future<void> update(AppSettings settings) async {
    value = settings;
    DesktopClipboardDiagnostics.configure(settings.clipboardTraceEnabled);
    await _preferences.setString(_storageKey, jsonEncode(settings.toJson()));
  }
}
