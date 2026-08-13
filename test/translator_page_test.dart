import 'package:dev_orbit/features/translator/deepl_api_key_store.dart';
import 'package:dev_orbit/features/translator/deepl_translation_client.dart';
import 'package:dev_orbit/features/translator/translator_controller.dart';
import 'package:dev_orbit/features/translator/translator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the translation workspace', (tester) async {
    final controller = TranslatorController(
      client: _NoopClient(),
      keyStore: _MemoryApiKeyStore(),
    );
    await tester.binding.setSurfaceSize(const Size(960, 700));

    await tester.pumpWidget(
      MaterialApp(home: TranslatorPage(controller: controller)),
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
      MaterialApp(home: TranslatorPage(controller: controller)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('translator-source')), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
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
