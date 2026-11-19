import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app_controller.dart';
import 'app/dev_orbit_app.dart';
import 'core/desktop/desktop_shell.dart';
import 'core/desktop/standalone_tool_window_launcher.dart';
import 'core/modules/tool_registry.dart';
import 'core/settings/settings_store.dart';
import 'features/json_formatter/json_formatter_module.dart';
import 'features/json_formatter/standalone_json_formatter_app.dart';
import 'features/sql_log/sql_log_module.dart';
import 'features/sql_log/standalone_sql_log_app.dart';
import 'features/sql_log/standalone_sql_log_constants.dart';
import 'features/text_compare/standalone_text_compare_app.dart';
import 'features/text_compare/standalone_text_compare_constants.dart';
import 'features/text_compare/text_compare_module.dart';
import 'features/timestamp/standalone_timestamp_app.dart';
import 'features/timestamp/standalone_timestamp_constants.dart';
import 'features/timestamp/timestamp_module.dart';
import 'features/translator/standalone_translator_app.dart';
import 'features/translator/standalone_translator_constants.dart';
import 'features/translator/translator_module.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.contains(standaloneJsonFormatterFlag)) {
    await runStandaloneJsonFormatter();
    return;
  }
  if (arguments.contains(standaloneTranslatorFlag)) {
    await runStandaloneTranslator();
    return;
  }
  if (arguments.contains(standaloneTextCompareFlag)) {
    await runStandaloneTextCompare();
    return;
  }
  if (arguments.contains(standaloneTimestampFlag)) {
    await runStandaloneTimestamp();
    return;
  }
  if (arguments.contains(standaloneSqlLogFlag)) {
    await runStandaloneSqlLog();
    return;
  }
  await hotKeyManager.unregisterAll();

  final settings = await SettingsStore.load();
  final jsonModule = JsonFormatterModule(settings);
  final translatorModule = TranslatorModule();
  final textCompareModule = TextCompareModule();
  final timestampModule = TimestampModule();
  final sqlLogModule = SqlLogModule();
  final registry = ToolRegistry([
    jsonModule,
    translatorModule,
    textCompareModule,
    timestampModule,
    sqlLogModule,
  ]);
  final controller = AppController(
    registry: registry,
    settings: settings,
    shell: NativeDesktopShell(),
    standaloneLauncher: NativeStandaloneToolWindowLauncher(),
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
