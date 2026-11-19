import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/desktop/standalone_window_activation.dart';
import '../../core/desktop/standalone_window_bootstrap.dart';
import '../../core/settings/settings_store.dart';
import 'sql_log_clipboard_import.dart';
import 'sql_log_controller.dart';
import 'sql_log_page.dart';
import 'standalone_sql_log_constants.dart';

Future<void> runStandaloneSqlLog() async {
  final lease = await acquireStandaloneInstance(sqlLogInstanceName);
  final settingsFuture = SettingsStore.load();
  await prepareStandaloneWindow(
    size: const Size(1100, 720),
    minimumSize: const Size(720, 560),
    title: standaloneSqlLogTitle,
  );
  final settings = await settingsFuture;
  runApp(_StandaloneSqlLogApp(settings: settings, instanceLease: lease));
}

class _StandaloneSqlLogApp extends StatefulWidget {
  const _StandaloneSqlLogApp({
    required this.settings,
    required this.instanceLease,
  });

  final SettingsStore settings;
  final SingleInstanceLease instanceLease;

  @override
  State<_StandaloneSqlLogApp> createState() => _StandaloneSqlLogAppState();
}

class _StandaloneSqlLogAppState extends State<_StandaloneSqlLogApp> {
  late final SqlLogController _controller;
  late final StandaloneWindowActivation _windowActivation;
  bool _didImportInitialClipboard = false;

  @override
  void initState() {
    super.initState();
    _controller = SqlLogController();
    _windowActivation = StandaloneWindowActivation(
      reactivateAfterClose: true,
      onActivated: _importClipboard,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_windowActivation.initialize()),
    );
  }

  Future<void> _importClipboard() async {
    if (_didImportInitialClipboard) return;
    _didImportInitialClipboard = true;
    await importSqlLogClipboard(
      controller: _controller,
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
        title: standaloneSqlLogTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: StandaloneWindowVisibility(
          activation: _windowActivation,
          child: StandaloneWindowShell(
            child: Scaffold(body: SqlLogPage(controller: _controller)),
          ),
        ),
      ),
    );
  }
}
