import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/desktop/standalone_window_activation.dart';
import '../../core/desktop/standalone_window_bootstrap.dart';
import '../../core/settings/settings_store.dart';
import 'standalone_timestamp_constants.dart';
import 'timestamp_page.dart';

Future<void> runStandaloneTimestamp() async {
  final lease = await acquireStandaloneInstance(timestampInstanceName);
  final settingsFuture = SettingsStore.load();
  await prepareStandaloneWindow(
    size: const Size(940, 650),
    minimumSize: const Size(660, 540),
    title: standaloneTimestampTitle,
  );
  final settings = await settingsFuture;
  runApp(_StandaloneTimestampApp(settings: settings, instanceLease: lease));
}

class _StandaloneTimestampApp extends StatefulWidget {
  const _StandaloneTimestampApp({
    required this.settings,
    required this.instanceLease,
  });

  final SettingsStore settings;
  final SingleInstanceLease instanceLease;

  @override
  State<_StandaloneTimestampApp> createState() =>
      _StandaloneTimestampAppState();
}

class _StandaloneTimestampAppState extends State<_StandaloneTimestampApp> {
  late final StandaloneWindowActivation _windowActivation;

  @override
  void initState() {
    super.initState();
    _windowActivation = StandaloneWindowActivation(onActivated: () async {});
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
        title: standaloneTimestampTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: StandaloneWindowVisibility(
          activation: _windowActivation,
          child: const StandaloneWindowShell(
            child: Scaffold(body: TimestampPage()),
          ),
        ),
      ),
    );
  }
}
