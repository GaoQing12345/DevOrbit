import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class AppSettings {
  const AppSettings({
    required this.hotKey,
    this.indentSize = 2,
    this.themeMode = ThemeMode.system,
    this.launchAtStartup = false,
    this.clipboardTraceEnabled = true,
  });

  factory AppSettings.defaults() {
    return AppSettings(
      hotKey: HotKey(
        identifier: 'dev-orbit-launcher',
        key: PhysicalKeyboardKey.space,
        modifiers: [
          Platform.isMacOS ? HotKeyModifier.meta : HotKeyModifier.control,
          HotKeyModifier.shift,
        ],
      ),
    );
  }

  final HotKey hotKey;
  final int indentSize;
  final ThemeMode themeMode;
  final bool launchAtStartup;
  final bool clipboardTraceEnabled;

  AppSettings copyWith({
    HotKey? hotKey,
    int? indentSize,
    ThemeMode? themeMode,
    bool? launchAtStartup,
    bool? clipboardTraceEnabled,
  }) {
    return AppSettings(
      hotKey: hotKey ?? this.hotKey,
      indentSize: indentSize ?? this.indentSize,
      themeMode: themeMode ?? this.themeMode,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      clipboardTraceEnabled:
          clipboardTraceEnabled ?? this.clipboardTraceEnabled,
    );
  }

  Map<String, Object> toJson() {
    return {
      'hotKey': jsonEncode(hotKey.toJson()),
      'indentSize': indentSize,
      'themeMode': themeMode.name,
      'launchAtStartup': launchAtStartup,
      'clipboardTraceEnabled': clipboardTraceEnabled,
    };
  }

  static AppSettings fromJson(Map<String, Object?> json) {
    final defaults = AppSettings.defaults();
    try {
      final hotKeyJson = jsonDecode(json['hotKey'] as String);
      return AppSettings(
        hotKey: HotKey.fromJson(hotKeyJson as Map<String, dynamic>),
        indentSize: json['indentSize'] == 4 ? 4 : 2,
        themeMode: ThemeMode.values.firstWhere(
          (mode) => mode.name == json['themeMode'],
          orElse: () => ThemeMode.system,
        ),
        launchAtStartup: json['launchAtStartup'] == true,
        clipboardTraceEnabled: json['clipboardTraceEnabled'] != false,
      );
    } catch (_) {
      return defaults;
    }
  }
}
