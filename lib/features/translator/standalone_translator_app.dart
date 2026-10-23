import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../core/desktop/desktop_window_shell.dart';
import '../../core/desktop/single_instance_registry.dart';
import '../../core/desktop/standalone_window_activation.dart';
import '../../core/desktop/standalone_window_bootstrap.dart';
import '../../core/settings/settings_store.dart';
import 'deepl_api_key_store.dart';
import 'deepl_translation_client.dart';
import 'standalone_translator_constants.dart';
import 'translator_controller.dart';
import 'translator_page.dart';

Future<void> runStandaloneTranslator() async {
  final lease = await acquireStandaloneInstance(translatorInstanceName);
  final settingsFuture = SettingsStore.load();
  await prepareStandaloneWindow(
    size: const Size(980, 700),
    minimumSize: const Size(720, 540),
    title: standaloneTranslatorTitle,
  );
  final settings = await settingsFuture;
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
  late final StandaloneWindowActivation _windowActivation;
  bool _didImportInitialClipboard = false;

  @override
  void initState() {
    super.initState();
    _controller = TranslatorController(
      client: DeepLTranslationClient(),
      keyStore: const NativeDeepLApiKeyStore(),
    );
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
    if (_controller.sourceText.isNotEmpty) return;
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (mounted && _controller.sourceText.isEmpty && text != null) {
        _controller.updateSource(text);
      }
    } on PlatformException {
      // 剪贴板不可用不应阻塞翻译窗口启动。
    }
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
        title: standaloneTranslatorTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.settings.value.themeMode,
        home: StandaloneWindowVisibility(
          activation: _windowActivation,
          child: StandaloneWindowShell(
            child: Scaffold(body: TranslatorPage(controller: _controller)),
          ),
        ),
      ),
    );
  }
}
