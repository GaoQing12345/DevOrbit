import 'package:dev_orbit/app/app_controller.dart';
import 'package:dev_orbit/core/desktop/desktop_shell.dart';
import 'package:dev_orbit/core/desktop/standalone_tool_window_launcher.dart';
import 'package:dev_orbit/core/modules/tool_registry.dart';
import 'package:dev_orbit/core/settings/settings_store.dart';
import 'package:dev_orbit/features/toolbox/toolbox_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Windows controls minimize and hide without quitting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final shell = _FakeDesktopShell();
    final controller = AppController(
      registry: ToolRegistry(const []),
      settings: settings,
      shell: shell,
      standaloneLauncher: _NoopStandaloneLauncher(),
    );
    await tester.binding.setSurfaceSize(const Size(960, 700));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolboxShell(
            controller: controller,
            registry: ToolRegistry(const []),
            settings: settings,
            showWindowControls: true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('最小化'));
    await tester.tap(find.byTooltip('关闭到后台'));
    await tester.pump();

    expect(shell.minimizeCount, 1);
    expect(shell.hideCount, 1);
    expect(shell.quitCount, 0);
    await tester.binding.setSurfaceSize(null);
  });
}

class _NoopStandaloneLauncher implements StandaloneToolWindowLauncher {
  @override
  Future<bool> openTool(String toolId) async => false;
}

class _FakeDesktopShell implements DesktopShell {
  int hideCount = 0;
  int minimizeCount = 0;
  int quitCount = 0;

  @override
  Future<void> hide() async => hideCount++;

  @override
  Future<String?> initialize(
    DesktopShellCallbacks callbacks,
    HotKey hotKey,
  ) async => null;

  @override
  Future<void> minimize() async => minimizeCount++;

  @override
  Future<void> quit() async => quitCount++;

  @override
  Future<bool> setLaunchAtStartup(bool enabled) async => true;

  @override
  Future<void> showRadial() async {}

  @override
  Future<void> showToolWindow({bool focus = true}) async {}

  @override
  Future<String?> updateHotKey(HotKey hotKey) async => null;
}
