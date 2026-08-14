import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/process_window_activator.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/settings/settings_store.dart';
import 'standalone_text_compare_constants.dart';
import 'text_compare_controller.dart';
import 'text_compare_page.dart';

Future<void> runStandaloneTextCompare() async {
  final instanceRegistry = FileSingleInstanceRegistry(textCompareInstanceName);
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
  final settings = await SettingsStore.load();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(false);
  final titleBarHeight = Platform.isWindows
      ? WindowsWindowTitleBar.height
      : 0.0;
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(1100, 720 + titleBarHeight),
      minimumSize: Size(820, 560 + titleBarHeight),
      center: true,
      backgroundColor: Colors.transparent,
      title: '文本比对 - DevOrbit',
    ),
  );
  runApp(_StandaloneTextCompareApp(settings: settings, instanceLease: lease));
}

class _StandaloneTextCompareApp extends StatefulWidget {
  const _StandaloneTextCompareApp({
    required this.settings,
    required this.instanceLease,
  });

  final SettingsStore settings;
  final SingleInstanceLease instanceLease;

  @override
  State<_StandaloneTextCompareApp> createState() =>
      _StandaloneTextCompareAppState();
}

class _StandaloneTextCompareAppState extends State<_StandaloneTextCompareApp> {
  late final TextCompareController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextCompareController();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_showWindow()),
    );
  }

  Future<void> _showWindow() async {
    await windowManager.setResizable(true);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    final useCustomWindowsTitleBar = Platform.isWindows;
    await windowManager.setTitleBarStyle(
      useCustomWindowsTitleBar ? TitleBarStyle.hidden : TitleBarStyle.normal,
      windowButtonVisibility: !useCustomWindowsTitleBar,
    );
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void dispose() {
    unawaited(widget.instanceLease.release());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, child) => MaterialApp(
        title: '文本比对 - DevOrbit',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: StandaloneWindowShell(
          title: '文本比对 - DevOrbit',
          child: Scaffold(body: TextComparePage(controller: _controller)),
        ),
      ),
    );
  }
}
