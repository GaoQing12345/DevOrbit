import 'dart:async';

import 'package:dev_orbit/app/app_controller.dart';
import 'package:dev_orbit/app/dev_orbit_app.dart';
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
  testWidgets('hidden main viewport is opaque outside radial mode', (
    tester,
  ) async {
    final fixture = await _ControllerFixture.create();
    await tester.pumpWidget(
      DevOrbitApp(
        controller: fixture.controller,
        registry: fixture.controller.registry,
        settings: fixture.controller.settings,
        startHidden: true,
      ),
    );
    await tester.pump();

    Material viewport() => tester.widget<Material>(
      find.byWidgetPredicate(
        (widget) => widget is Material && widget.child is Stack,
      ),
    );

    expect(viewport().color, isNot(Colors.transparent));

    await fixture.controller.toggleRadial();
    await tester.pump();

    expect(viewport().color, Colors.transparent);
  });

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
    expect(fixture.shell.radialHideCount, 1);
    expect(fixture.shell.toolWindowShows, 1);
  });

  test(
    'transient blur while radial is opening does not show a white window',
    () async {
      final opening = Completer<void>();
      final fixture = await _ControllerFixture.create(
        onShowRadial: () => opening.future,
      );
      await fixture.controller.initialize();

      final showing = fixture.controller.toggleRadial();
      await Future<void>.delayed(Duration.zero);
      fixture.shell.callbacks!.onWindowBlur();
      await Future<void>.delayed(Duration.zero);

      expect(fixture.controller.mode, AppViewMode.radial);
      expect(fixture.shell.radialHideCount, 0);

      opening.complete();
      await showing;
      expect(fixture.controller.mode, AppViewMode.radial);
    },
  );

  test('warms standalone tools while the desktop shell initializes', () async {
    final fixture = await _ControllerFixture.create();

    await fixture.controller.initialize();

    expect(fixture.launcher.warmUpCount, 1);
  });

  test('background startup hides without re-reading window bounds', () async {
    final fixture = await _ControllerFixture.create();

    await fixture.controller.afterFirstFrame(startHidden: true);

    expect(fixture.shell.radialHideCount, 1);
    expect(fixture.shell.hideCount, 0);
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
    expect(fixture.shell.radialHideCount, 2);
  });

  test('radial hides before a standalone process finishes starting', () async {
    final launchCompleter = Completer<bool>();
    final fixture = await _ControllerFixture.create(
      modules: [_TestModule(id: 'json-formatter')],
      launcher: _FakeStandaloneLauncher(onOpen: (_) => launchCompleter.future),
    );

    final opening = fixture.controller.openTool(
      'json-formatter',
      origin: ToolLaunchOrigin.radial,
    );
    await Future<void>.delayed(Duration.zero);

    expect(fixture.controller.mode, AppViewMode.hidden);
    expect(fixture.shell.radialHideCount, 1);
    launchCompleter.complete(true);
    await opening;
  });

  test('standalone activation does not wait for radial hiding', () async {
    final hideCompleter = Completer<void>();
    final fixture = await _ControllerFixture.create(
      modules: [_TestModule(id: 'json-formatter')],
      onHideRadial: () => hideCompleter.future,
    );

    final opening = fixture.controller.openTool(
      'json-formatter',
      origin: ToolLaunchOrigin.radial,
    );
    await Future<void>.delayed(Duration.zero);

    expect(fixture.launcher.openedToolIds, ['json-formatter']);
    expect(fixture.shell.radialHideCount, 1);
    hideCompleter.complete();
    await opening;
  });

  test('native close hides the toolbox without quitting the app', () async {
    final fixture = await _ControllerFixture.create();
    await fixture.controller.initialize();

    await fixture.shell.callbacks!.onCloseRequested();

    expect(fixture.shell.hideCount, 1);
    expect(fixture.shell.quitCount, 0);
  });

  test('tray quit closes standalone tools before the main process', () async {
    final closeCompleter = Completer<void>();
    final fixture = await _ControllerFixture.create(
      launcher: _FakeStandaloneLauncher(
        onCloseAll: () => closeCompleter.future,
      ),
    );
    await fixture.controller.initialize();

    final quitting = fixture.shell.callbacks!.onQuitRequested();
    await Future<void>.delayed(Duration.zero);

    expect(fixture.launcher.closeAllCount, 1);
    expect(fixture.shell.quitCount, 0);
    closeCompleter.complete();
    await quitting;
    expect(fixture.shell.quitCount, 1);
  });
}

class _FailingDesktopShell implements DesktopShell {
  @override
  Future<void> hideRadial() async {}

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
    _FakeStandaloneLauncher? launcher,
    Future<void> Function()? onHideRadial,
    Future<void> Function()? onShowRadial,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final shell = _FakeDesktopShell(
      onHideRadial: onHideRadial,
      onShowRadial: onShowRadial,
    );
    launcher ??= _FakeStandaloneLauncher();
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
  _FakeStandaloneLauncher({this.onOpen, this.onCloseAll});

  final Future<bool> Function(String toolId)? onOpen;
  final Future<void> Function()? onCloseAll;
  final List<String> openedToolIds = [];
  int closeAllCount = 0;
  int warmUpCount = 0;

  @override
  Future<void> warmUp() async => warmUpCount++;

  @override
  Future<void> closeAllTools() async {
    closeAllCount++;
    await onCloseAll?.call();
  }

  @override
  Future<bool> openTool(String toolId) async {
    openedToolIds.add(toolId);
    if (onOpen != null) return onOpen!(toolId);
    return toolId == 'json-formatter';
  }
}

class _FakeDesktopShell extends _FailingDesktopShell {
  _FakeDesktopShell({this.onHideRadial, this.onShowRadial});

  final Future<void> Function()? onHideRadial;
  final Future<void> Function()? onShowRadial;
  int hideCount = 0;
  int radialHideCount = 0;
  int quitCount = 0;
  int toolWindowShows = 0;
  DesktopShellCallbacks? callbacks;

  @override
  Future<void> hide() async => hideCount++;

  @override
  Future<void> hideRadial() async {
    radialHideCount++;
    await onHideRadial?.call();
  }

  @override
  Future<void> showRadial() async {
    await onShowRadial?.call();
  }

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
