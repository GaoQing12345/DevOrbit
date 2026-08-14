import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/process_window_activator.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/settings/settings_store.dart';
import 'deepl_api_key_store.dart';
import 'deepl_translation_client.dart';
import 'standalone_translator_constants.dart';
import 'translator_controller.dart';
import 'translator_page.dart';

Future<void> runStandaloneTranslator() async {
  final instanceRegistry = FileSingleInstanceRegistry(translatorInstanceName);
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
      size: Size(980, 700 + titleBarHeight),
      minimumSize: Size(720, 540 + titleBarHeight),
      center: true,
      backgroundColor: Colors.transparent,
      title: '文本翻译 - DevOrbit',
    ),
  );
  runApp(_StandaloneTranslatorApp(settings: settings, instanceLease: lease));
}

class _StandaloneTranslatorApp extends StatefulWidget {
  const _StandaloneTranslatorApp({
    required this.settings,
    required this.instanceLease,
  });

  final SettingsStore settings;
  final SingleInstanceLease instanceLease;

  @override
  State<_StandaloneTranslatorApp> createState() =>
      _StandaloneTranslatorAppState();
}

class _StandaloneTranslatorAppState extends State<_StandaloneTranslatorApp> {
  late final TranslatorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TranslatorController(
      client: DeepLTranslationClient(),
      keyStore: const NativeDeepLApiKeyStore(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_initializeWindow()),
    );
  }

  Future<void> _initializeWindow() async {
    await _showWindow();
    if (!mounted || _controller.sourceText.isNotEmpty) return;
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (mounted && _controller.sourceText.isEmpty && text != null) {
        _controller.updateSource(text);
      }
    } on PlatformException {
      // 剪贴板不可用不应阻塞翻译窗口启动。
    }
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
        title: '文本翻译 - DevOrbit',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: StandaloneWindowShell(
          title: '文本翻译 - DevOrbit',
          child: Scaffold(body: TranslatorPage(controller: _controller)),
        ),
      ),
    );
  }
}
