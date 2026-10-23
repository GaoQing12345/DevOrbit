import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/desktop/standalone_window_activation.dart';
import '../../core/desktop/standalone_window_bootstrap.dart';
import '../../core/settings/settings_store.dart';
import 'standalone_text_compare_constants.dart';
import 'text_compare_controller.dart';
import 'text_compare_page.dart';

Future<void> runStandaloneTextCompare() async {
  final lease = await acquireStandaloneInstance(textCompareInstanceName);
  final settingsFuture = SettingsStore.load();
  await prepareStandaloneWindow(
    size: const Size(1100, 720),
    minimumSize: const Size(820, 560),
    title: standaloneTextCompareTitle,
  );
  final settings = await settingsFuture;
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
  late final StandaloneWindowActivation _windowActivation;

  @override
  void initState() {
    super.initState();
    _controller = TextCompareController();
    _windowActivation = StandaloneWindowActivation(onActivated: () async {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_windowActivation.initialize()),
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
        title: standaloneTextCompareTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: StandaloneWindowVisibility(
          activation: _windowActivation,
          child: StandaloneWindowShell(
            child: Scaffold(body: TextComparePage(controller: _controller)),
          ),
        ),
      ),
    );
  }
}
