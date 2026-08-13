import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_theme.dart';
import '../../core/settings/settings_store.dart';
import 'deepl_api_key_store.dart';
import 'deepl_translation_client.dart';
import 'translator_controller.dart';
import 'translator_page.dart';

const standaloneTranslatorFlag = '--translator-window';

Future<void> runStandaloneTranslator() async {
  final settings = await SettingsStore.load();
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(false);
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(980, 700),
      minimumSize: Size(720, 540),
      center: true,
      backgroundColor: Colors.transparent,
      title: '文本翻译 - DevOrbit',
    ),
  );
  final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
  runApp(
    _StandaloneTranslatorApp(settings: settings, initialText: clipboard?.text),
  );
}

class _StandaloneTranslatorApp extends StatefulWidget {
  const _StandaloneTranslatorApp({required this.settings, this.initialText});

  final SettingsStore settings;
  final String? initialText;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWindow());
  }

  Future<void> _showWindow() async {
    await windowManager.setResizable(true);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void dispose() {
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
        home: Scaffold(
          body: TranslatorPage(
            controller: _controller,
            initialText: widget.initialText,
          ),
        ),
      ),
    );
  }
}
