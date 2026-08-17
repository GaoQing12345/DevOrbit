import 'package:dev_orbit/app/app_theme.dart';
import 'package:dev_orbit/features/translator/deepl_api_key_store.dart';
import 'package:dev_orbit/features/translator/deepl_translation_client.dart';
import 'package:dev_orbit/features/translator/translator_controller.dart';
import 'package:dev_orbit/features/translator/translator_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('shows the translation workspace', (tester) async {
    final controller = TranslatorController(
      client: _NoopClient(),
      keyStore: _MemoryApiKeyStore(),
    );
    await tester.binding.setSurfaceSize(const Size(960, 700));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: TranslatorPage(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('自动检测'), findsOneWidget);
    expect(find.text('翻译为'), findsWidgets);
    expect(find.byKey(const ValueKey('translator-source')), findsOneWidget);
    expect(find.text('译文会显示在这里'), findsOneWidget);
    expect(find.text('尚未配置 DeepL API Key'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('fits the standalone minimum window', (tester) async {
    final controller = TranslatorController(
      client: _NoopClient(),
      keyStore: _MemoryApiKeyStore(),
    );
    await tester.binding.setSurfaceSize(const Size(720, 540));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: TranslatorPage(controller: controller),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('translator-source')), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('QuickClipboard inserts into the previous translation cursor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TranslatorController(
      client: _NoopClient(),
      keyStore: _MemoryApiKeyStore(),
    );
    addTearDown(controller.dispose);
    mockClipboard(tester, initialText: 'restored clipboard');
    final nativeClipboard = mockClipboardRevision(tester);
    await tester.pumpWidget(
      MaterialApp(home: TranslatorPage(controller: controller)),
    );
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('translator-source')),
    );
    field.controller!.value = const TextEditingValue(
      text: 'abcd',
      selection: TextSelection.collapsed(offset: 2),
    );
    field.focusNode!.requestFocus();
    await tester.pump();

    await _sendWindowEvent('blur');
    field.focusNode!.unfocus();
    await tester.pump();
    nativeClipboard.pendingPasteText = 'QuickClipboard';
    await _sendWindowEvent('focus');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(field.controller!.text, 'abQuickClipboardcd');
    expect(controller.sourceText, 'abQuickClipboardcd');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _sendWindowEvent(String eventName) async {
  windowManager.hasListeners;
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('onEvent', {'eventName': eventName}),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('window_manager', message, (_) {});
}

class _NoopClient implements TranslationClient {
  @override
  void cancel() {}

  @override
  Future<TranslationResult> translate({
    required String apiKey,
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async => const TranslationResult(text: '', detectedSource: 'EN');
}

class _MemoryApiKeyStore implements DeepLApiKeyStore {
  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}
