import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_theme.dart';
import '../../core/settings/settings_store.dart';
import 'json_document_controller.dart';
import 'json_formatter_page.dart';
import 'json_initial_clipboard_import.dart';

Future<void> runStandaloneJsonFormatter() async {
  final settings = await SettingsStore.load();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(false);
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(960, 700),
      minimumSize: Size(720, 520),
      center: true,
      backgroundColor: Colors.transparent,
      title: 'JSON 格式化 - DevOrbit',
    ),
  );
  runApp(_StandaloneJsonFormatterApp(settings: settings));
}

class _StandaloneJsonFormatterApp extends StatefulWidget {
  const _StandaloneJsonFormatterApp({required this.settings});

  final SettingsStore settings;

  @override
  State<_StandaloneJsonFormatterApp> createState() =>
      _StandaloneJsonFormatterAppState();
}

class _StandaloneJsonFormatterAppState
    extends State<_StandaloneJsonFormatterApp> {
  late final JsonDocumentController _controller;

  @override
  void initState() {
    super.initState();
    _controller = JsonDocumentController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeWindow());
  }

  Future<void> _initializeWindow() async {
    await importInitialClipboardJson(
      controller: _controller,
      indentSize: widget.settings.value.indentSize,
      readClipboard: () => Clipboard.getData(Clipboard.kTextPlain),
    );
    if (mounted) await _showWindow();
  }

  Future<void> _showWindow() async {
    await windowManager.setResizable(true);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, child) => MaterialApp(
        title: 'JSON 格式化 - DevOrbit',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: Scaffold(
          body: JsonFormatterPage(
            controller: _controller,
            settings: widget.settings,
          ),
        ),
      ),
    );
  }
}
