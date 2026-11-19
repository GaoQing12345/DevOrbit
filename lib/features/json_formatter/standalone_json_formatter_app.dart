import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/desktop/standalone_window_activation.dart';
import '../../core/desktop/standalone_window_bootstrap.dart';
import '../../core/settings/settings_store.dart';
import 'json_document_controller.dart';
import 'json_formatter_page.dart';
import 'json_initial_clipboard_import.dart';
import 'standalone_json_formatter_constants.dart';

Future<void> runStandaloneJsonFormatter() async {
  final lease = await acquireStandaloneInstance(jsonFormatterInstanceName);
  final settingsFuture = SettingsStore.load();
  await prepareStandaloneWindow(
    size: const Size(960, 700),
    minimumSize: const Size(720, 520),
    title: standaloneJsonFormatterTitle,
  );
  final settings = await settingsFuture;
  runApp(_StandaloneJsonFormatterApp(settings: settings, instanceLease: lease));
}

class _StandaloneJsonFormatterApp extends StatefulWidget {
  const _StandaloneJsonFormatterApp({
    required this.settings,
    required this.instanceLease,
  });

  final SettingsStore settings;
  final SingleInstanceLease instanceLease;

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
    unawaited(widget.instanceLease.release());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, child) => MaterialApp(
        title: standaloneJsonFormatterTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: StandaloneWindowVisibility(
          activation: _windowActivation,
          child: StandaloneWindowShell(
            child: Scaffold(
              body: JsonFormatterPage(
                controller: _controller,
                settings: widget.settings,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
