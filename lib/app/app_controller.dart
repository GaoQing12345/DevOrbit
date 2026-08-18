import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../core/desktop/desktop_shell.dart';
import '../core/desktop/standalone_tool_window_launcher.dart';
import '../core/modules/tool_module.dart';
import '../core/modules/tool_registry.dart';
import '../core/settings/settings_store.dart';

enum AppViewMode { hidden, radial, toolbox, tool }

enum ToolboxSection { home, settings }

class AppController extends ChangeNotifier {
  AppController({
    required this.registry,
    required this.settings,
    required this.shell,
    required this.standaloneLauncher,
  });

  final ToolRegistry registry;
  final SettingsStore settings;
  final DesktopShell shell;
  final StandaloneToolWindowLauncher standaloneLauncher;

  AppViewMode _mode = AppViewMode.hidden;
  ToolboxSection _section = ToolboxSection.home;
  String? _selectedToolId;
  String? _hotKeyError;

  AppViewMode get mode => _mode;
  ToolboxSection get section => _section;
  String? get selectedToolId => _selectedToolId;
  String? get hotKeyError => _hotKeyError;

  Future<void> initialize() async {
    unawaited(standaloneLauncher.warmUp());
    _hotKeyError = await shell.initialize(
      DesktopShellCallbacks(
        onToggleRadial: toggleRadial,
        onOpenToolbox: showToolbox,
        onOpenSettings: showSettings,
        onCloseRequested: hide,
        onQuitRequested: quit,
        onWindowBlur: _handleWindowBlur,
      ),
      settings.value.hotKey,
    );
    notifyListeners();
  }

  Future<void> afterFirstFrame({required bool startHidden}) async {
    if (startHidden) {
      await shell.hideRadial();
    } else {
      await showToolbox();
    }
  }

  Future<void> toggleRadial() async {
    if (_mode == AppViewMode.radial) {
      await dismissRadial();
      return;
    }
    _mode = AppViewMode.radial;
    notifyListeners();
    await shell.showRadial();
  }

  Future<void> dismissRadial() async {
    _mode = AppViewMode.hidden;
    notifyListeners();
    await shell.hideRadial();
  }

  Future<void> showToolbox() async {
    _mode = AppViewMode.toolbox;
    _section = ToolboxSection.home;
    notifyListeners();
    await shell.showToolWindow();
  }

  Future<void> showSettings() async {
    _mode = AppViewMode.toolbox;
    _section = ToolboxSection.settings;
    notifyListeners();
    await shell.showToolWindow();
  }

  Future<void> openTool(
    String id, {
    ToolLaunchOrigin origin = ToolLaunchOrigin.toolbox,
  }) async {
    final module = registry.byId(id);
    if (origin == ToolLaunchOrigin.radial) {
      _mode = AppViewMode.hidden;
      notifyListeners();
      final hidingRadial = shell.hideRadial();
      final openedStandalone = await standaloneLauncher.openTool(id);
      await hidingRadial;
      if (openedStandalone) return;
    }
    await module.onLaunch(ToolLaunchContext(origin: origin));
    _selectedToolId = id;
    _mode = AppViewMode.tool;
    notifyListeners();
    await shell.showToolWindow();
  }

  Future<void> hide() async {
    _mode = AppViewMode.hidden;
    notifyListeners();
    await shell.hide();
  }

  Future<void> minimize() {
    return shell.minimize();
  }

  Future<void> quit() async {
    await standaloneLauncher.closeAllTools();
    await shell.quit();
  }

  Future<void> updateHotKey(HotKey hotKey) async {
    final error = await shell.updateHotKey(hotKey);
    _hotKeyError = error;
    if (error == null) {
      await settings.update(settings.value.copyWith(hotKey: hotKey));
    }
    notifyListeners();
  }

  Future<void> updateIndent(int indentSize) {
    return settings.update(settings.value.copyWith(indentSize: indentSize));
  }

  Future<void> updateTheme(ThemeMode themeMode) {
    return settings.update(settings.value.copyWith(themeMode: themeMode));
  }

  Future<void> updateLaunchAtStartup(bool enabled) async {
    final success = await shell.setLaunchAtStartup(enabled);
    if (!success) return;
    await settings.update(settings.value.copyWith(launchAtStartup: enabled));
  }

  Future<void> updateClipboardTrace(bool enabled) {
    return settings.update(
      settings.value.copyWith(clipboardTraceEnabled: enabled),
    );
  }

  void _handleWindowBlur() {
    if (_mode == AppViewMode.radial) dismissRadial();
  }
}
