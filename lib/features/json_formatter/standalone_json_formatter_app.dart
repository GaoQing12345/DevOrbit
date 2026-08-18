import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/standalone_window_activation.dart';
import '../../core/settings/settings_store.dart';
import 'json_document_controller.dart';
import 'json_formatter_page.dart';
import 'json_initial_clipboard_import.dart';

Future<void> runStandaloneJsonFormatter({bool prewarmed = false}) async {
  final settingsFuture = SettingsStore.load();
  await windowManager.ensureInitialized();
  final useCustomWindowsTitleBar = Platform.isWindows;
  final titleBarHeight = useCustomWindowsTitleBar
      ? WindowsWindowTitleBar.height
      : 0.0;
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(960, 700 + titleBarHeight),
      minimumSize: Size(720, 520 + titleBarHeight),
      center: true,
      // Standalone tools are helper windows owned by the main app. Keep each
      // helper process out of the macOS Dock, including after window_manager
      // applies the WindowOptions.
      skipTaskbar: true,
      backgroundColor: Colors.transparent,
      title: 'JSON 格式化 - DevOrbit',
      titleBarStyle: useCustomWindowsTitleBar
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: !useCustomWindowsTitleBar,
    ),
  );
  final settings = await settingsFuture;
  runApp(_StandaloneJsonFormatterApp(settings: settings, prewarmed: prewarmed));
}

class _StandaloneJsonFormatterApp extends StatefulWidget {
  const _StandaloneJsonFormatterApp({
    required this.settings,
    required this.prewarmed,
  });

  final SettingsStore settings;
  final bool prewarmed;

  @override
  State<_StandaloneJsonFormatterApp> createState() =>
      _StandaloneJsonFormatterAppState();
}

class _StandaloneJsonFormatterAppState
    extends State<_StandaloneJsonFormatterApp> {
  late final JsonDocumentController _controller;
  late final StandaloneWindowActivation _windowActivation;
  bool _didImportInitialClipboard = false;

  @override
  void initState() {
    super.initState();
    _controller = JsonDocumentController();
    _windowActivation = StandaloneWindowActivation(
      prewarmed: widget.prewarmed,
      onActivated: _importClipboard,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_windowActivation.initialize()),
    );
  }

  Future<void> _importClipboard() async {
    if (!mounted || _didImportInitialClipboard) return;
    _didImportInitialClipboard = true;
    await importInitialClipboardJson(
      controller: _controller,
      indentSize: widget.settings.value.indentSize,
      readClipboard: () => Clipboard.getData(Clipboard.kTextPlain),
    );
  }

  @override
  void dispose() {
    _windowActivation.dispose();
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
        home: StandaloneWindowShell(
          title: 'JSON 格式化 - DevOrbit',
          child: Scaffold(
            body: JsonFormatterPage(
              controller: _controller,
              settings: widget.settings,
            ),
          ),
        ),
      ),
    );
  }
}
