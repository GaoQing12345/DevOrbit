import 'package:dev_orbit/app/app_controller.dart';
import 'package:dev_orbit/core/desktop/desktop_shell.dart';
import 'package:dev_orbit/core/desktop/standalone_tool_window_launcher.dart';
import 'package:dev_orbit/core/modules/tool_module.dart';
import 'package:dev_orbit/core/modules/tool_registry.dart';
import 'package:dev_orbit/core/settings/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('keeps the initial hotkey registration error', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final controller = AppController(
      registry: ToolRegistry(const []),
      settings: settings,
      shell: _FailingDesktopShell(),
      standaloneLauncher: _FakeStandaloneLauncher(),
    );

    await controller.initialize();

    expect(controller.hotKeyError, '快捷键已被占用');
  });

  test('shortcut from settings opens radial and dismiss hides it', () async {
    final fixture = await _ControllerFixture.create();
    await fixture.controller.showSettings();

    await fixture.controller.toggleRadial();
    expect(fixture.controller.mode, AppViewMode.radial);

    await fixture.controller.dismissRadial();
    expect(fixture.controller.mode, AppViewMode.hidden);
    expect(fixture.shell.hideCount, 1);
    expect(fixture.shell.toolWindowShows, 1);
  });

  test('each radial JSON selection opens a standalone window', () async {
    final fixture = await _ControllerFixture.create(
      modules: [_TestModule(id: 'json-formatter')],
    );

    await fixture.controller.openTool(
      'json-formatter',
      origin: ToolLaunchOrigin.radial,
    );
    await fixture.controller.openTool(
      'json-formatter',
      origin: ToolLaunchOrigin.radial,
    );

    expect(fixture.launcher.openedToolIds, [
      'json-formatter',
      'json-formatter',
    ]);
    expect(fixture.controller.mode, AppViewMode.hidden);
    expect(fixture.shell.hideCount, 2);
  });

  test('native close hides the toolbox without quitting the app', () async {
    final fixture = await _ControllerFixture.create();
    await fixture.controller.initialize();

    await fixture.shell.callbacks!.onCloseRequested();

    expect(fixture.shell.hideCount, 1);
    expect(fixture.shell.quitCount, 0);
  });
}

class _FailingDesktopShell implements DesktopShell {
  @override
  Future<void> hide() async {}

  @override
  Future<void> minimize() async {}

  @override
  Future<String?> initialize(
    DesktopShellCallbacks callbacks,
    HotKey hotKey,
  ) async => '快捷键已被占用';

  @override
  Future<void> quit() async {}

  @override
  Future<bool> setLaunchAtStartup(bool enabled) async => true;

  @override
  Future<void> showRadial() async {}

  @override
  Future<void> showToolWindow({bool focus = true}) async {}

  @override
  Future<String?> updateHotKey(HotKey hotKey) async => null;
}

class _ControllerFixture {
  _ControllerFixture(this.controller, this.shell, this.launcher);

  final AppController controller;
  final _FakeDesktopShell shell;
  final _FakeStandaloneLauncher launcher;

  static Future<_ControllerFixture> create({
    List<ToolModule> modules = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final shell = _FakeDesktopShell();
    final launcher = _FakeStandaloneLauncher();
    final controller = AppController(
      registry: ToolRegistry(modules),
      settings: settings,
      shell: shell,
      standaloneLauncher: launcher,
    );
    return _ControllerFixture(controller, shell, launcher);
  }
}

class _FakeStandaloneLauncher implements StandaloneToolWindowLauncher {
  final List<String> openedToolIds = [];

  @override
  Future<bool> openTool(String toolId) async {
    openedToolIds.add(toolId);
    return toolId == 'json-formatter';
  }
}

class _FakeDesktopShell extends _FailingDesktopShell {
  int hideCount = 0;
  int quitCount = 0;
  int toolWindowShows = 0;
  DesktopShellCallbacks? callbacks;

  @override
  Future<void> hide() async => hideCount++;

  @override
  Future<String?> initialize(
    DesktopShellCallbacks callbacks,
    HotKey hotKey,
  ) async {
    this.callbacks = callbacks;
    return null;
  }

  @override
  Future<void> quit() async => quitCount++;

  @override
  Future<void> showToolWindow({bool focus = true}) async {
    toolWindowShows++;
  }
}

class _TestModule implements ToolModule {
  _TestModule({required this.id});

  final String id;

  @override
  ToolDescriptor get descriptor => ToolDescriptor(
    id: id,
    title: id,
    description: id,
    icon: Icons.data_object_rounded,
    radialSlot: 0,
    accentColor: Colors.teal,
  );

  @override
  Widget buildPage() => const SizedBox();

  @override
  Future<void> onLaunch(ToolLaunchContext context) async {}
}
