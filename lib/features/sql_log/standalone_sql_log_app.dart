import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/process_window_activator.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/desktop/standalone_window_activation.dart';
import '../../core/settings/settings_store.dart';
import 'sql_log_clipboard_import.dart';
import 'sql_log_controller.dart';
import 'sql_log_page.dart';
import 'standalone_sql_log_constants.dart';

Future<void> runStandaloneSqlLog({bool prewarmed = false}) async {
  final instanceRegistry = FileSingleInstanceRegistry(sqlLogInstanceName);
  final lease = await instanceRegistry.tryAcquire(pid);
  if (lease == null) {
    try {
      final processId = await instanceRegistry.findProcessId();
      if (processId != null) {
        await NativeProcessWindowActivator().activate(processId);
      }
    } finally {
      exit(0);
    }
  }

  final settingsFuture = SettingsStore.load();
  await windowManager.ensureInitialized();
  final useCustomWindowsTitleBar = Platform.isWindows;
  final titleBarHeight = useCustomWindowsTitleBar
      ? WindowsWindowTitleBar.height
      : 0.0;
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(1100, 720 + titleBarHeight),
      minimumSize: Size(720, 560 + titleBarHeight),
      center: true,
      skipTaskbar: true,
      backgroundColor: Colors.transparent,
      title: 'SQL 日志还原 - DevOrbit',
      titleBarStyle: useCustomWindowsTitleBar
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: !useCustomWindowsTitleBar,
    ),
  );
  final settings = await settingsFuture;
  runApp(
    _StandaloneSqlLogApp(
      settings: settings,
      instanceLease: lease,
      prewarmed: prewarmed,
    ),
  );
}

class _StandaloneSqlLogApp extends StatefulWidget {
  const _StandaloneSqlLogApp({
    required this.settings,
    required this.instanceLease,
    required this.prewarmed,
  });

  final SettingsStore settings;
  final SingleInstanceLease instanceLease;
  final bool prewarmed;

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
      prewarmed: widget.prewarmed,
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
        title: 'SQL 日志还原 - DevOrbit',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: StandaloneWindowShell(
          title: 'SQL 日志还原 - DevOrbit',
          child: Scaffold(body: SqlLogPage(controller: _controller)),
        ),
      ),
    );
  }
}
