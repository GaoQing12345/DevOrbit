import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/process_window_activator.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/desktop/standalone_window_activation.dart';
import '../../core/settings/settings_store.dart';
import 'standalone_timestamp_constants.dart';
import 'timestamp_page.dart';

Future<void> runStandaloneTimestamp({bool prewarmed = false}) async {
  final instanceRegistry = FileSingleInstanceRegistry(timestampInstanceName);
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
      size: Size(940, 650 + titleBarHeight),
      minimumSize: Size(660, 540 + titleBarHeight),
      center: true,
      skipTaskbar: true,
      backgroundColor: Colors.transparent,
      title: '时间戳转换 - DevOrbit',
      titleBarStyle: useCustomWindowsTitleBar
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: !useCustomWindowsTitleBar,
    ),
  );
  final settings = await settingsFuture;
  runApp(
    _StandaloneTimestampApp(
      settings: settings,
      instanceLease: lease,
      prewarmed: prewarmed,
    ),
  );
}

class _StandaloneTimestampApp extends StatefulWidget {
  const _StandaloneTimestampApp({
    required this.settings,
    required this.instanceLease,
    required this.prewarmed,
  });

  final SettingsStore settings;
  final SingleInstanceLease instanceLease;
  final bool prewarmed;

  @override
  State<_StandaloneTimestampApp> createState() =>
      _StandaloneTimestampAppState();
}

class _StandaloneTimestampAppState extends State<_StandaloneTimestampApp> {
  late final StandaloneWindowActivation _windowActivation;

  @override
  void initState() {
    super.initState();
    _windowActivation = StandaloneWindowActivation(
      prewarmed: widget.prewarmed,
      onActivated: () async {},
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_windowActivation.initialize()),
    );
  }

  @override
  void dispose() {
    _windowActivation.dispose();
    unawaited(widget.instanceLease.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, child) => MaterialApp(
        title: '时间戳转换 - DevOrbit',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: const StandaloneWindowShell(
          title: '时间戳转换 - DevOrbit',
          child: Scaffold(body: TimestampPage()),
        ),
      ),
    );
  }
}
