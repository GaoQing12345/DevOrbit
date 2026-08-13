import 'package:dev_orbit/features/translator/deepl_api_key_store.dart';
import 'package:dev_orbit/features/translator/deepl_translation_client.dart';
import 'package:dev_orbit/features/translator/translator_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires an API key before translating', () async {
    final controller = TranslatorController(
      client: _FakeTranslationClient(),
      keyStore: _MemoryApiKeyStore(),
    )..updateSource('Hello');

    await controller.translate();

    expect(controller.errorMessage, '请先配置 DeepL API Key');
    expect(controller.translatedText, isEmpty);
  });

  test('translates with automatic source detection', () async {
    final client = _FakeTranslationClient();
    final controller =
        TranslatorController(
            client: client,
            keyStore: _MemoryApiKeyStore('secret'),
          )
          ..updateSource('Hello')
          ..updateTargetLanguage('ZH-HANS');

    await controller.translate();

    expect(client.sourceLanguage, isNull);
    expect(client.targetLanguage, 'ZH-HANS');
    expect(controller.translatedText, '你好');
    expect(controller.detectedSourceLanguage, 'EN');
    expect(controller.errorMessage, isNull);
  });

  test('swaps translated content and language direction', () async {
    final controller =
        TranslatorController(
            client: _FakeTranslationClient(),
            keyStore: _MemoryApiKeyStore('secret'),
          )
          ..updateSource('Hello')
          ..updateTargetLanguage('ZH-HANS');
    await controller.translate();

    controller.swap();

    expect(controller.sourceText, '你好');
    expect(controller.translatedText, 'Hello');
    expect(controller.targetLanguage, 'EN-US');
    expect(controller.detectedSourceLanguage, 'ZH');
  });
}

class _FakeTranslationClient implements TranslationClient {
  String? sourceLanguage;
  String? targetLanguage;

  @override
  void cancel() {}

  @override
  Future<TranslationResult> translate({
    required String apiKey,
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    this.sourceLanguage = sourceLanguage;
    this.targetLanguage = targetLanguage;
    return const TranslationResult(text: '你好', detectedSource: 'EN');
  }
}

class _MemoryApiKeyStore implements DeepLApiKeyStore {
  _MemoryApiKeyStore([this.value]);

  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}
