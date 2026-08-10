import 'package:dev_orbit/app/app_controller.dart';
import 'package:dev_orbit/core/desktop/desktop_shell.dart';
import 'package:dev_orbit/core/modules/tool_registry.dart';
import 'package:dev_orbit/core/settings/settings_store.dart';
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
    );

    await controller.initialize();

    expect(controller.hotKeyError, '快捷键已被占用');
  });
}

class _FailingDesktopShell implements DesktopShell {
  @override
  Future<void> hide() async {}

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
