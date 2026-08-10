import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'app/app_controller.dart';
import 'app/dev_orbit_app.dart';
import 'core/desktop/desktop_shell.dart';
import 'core/modules/tool_registry.dart';
import 'core/settings/settings_store.dart';
import 'features/json_formatter/json_formatter_module.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await hotKeyManager.unregisterAll();

  final settings = await SettingsStore.load();
  final jsonModule = JsonFormatterModule(settings);
  final registry = ToolRegistry([jsonModule]);
  final controller = AppController(
    registry: registry,
    settings: settings,
    shell: NativeDesktopShell(),
  );
  await controller.initialize();

  runApp(
    DevOrbitApp(
      controller: controller,
      registry: registry,
      settings: settings,
      startHidden: arguments.contains('--hidden'),
    ),
  );
}
