import 'package:flutter/foundation.dart';

import 'deepl_api_key_store.dart';
import 'deepl_translation_client.dart';
import 'translation_language.dart';

class TranslatorController extends ChangeNotifier {
  TranslatorController({
    required TranslationClient client,
    required DeepLApiKeyStore keyStore,
  }) : this._(client, keyStore);

  TranslatorController._(this._client, this._keyStore);

  final TranslationClient _client;
  final DeepLApiKeyStore _keyStore;

  String sourceText = '';
  String translatedText = '';
  String targetLanguage = 'ZH-HANS';
  String? detectedSourceLanguage;
  String? errorMessage;
  bool isTranslating = false;
  bool hasApiKey = false;
  int _requestVersion = 0;

  Future<void> initialize() async {
    try {
      final key = await _keyStore.read();
      hasApiKey = key != null && key.trim().isNotEmpty;
    } on Object {
      hasApiKey = false;
      errorMessage = '无法访问系统安全存储';
    }
    notifyListeners();
  }

  void updateSource(String value) {
    sourceText = value;
    errorMessage = null;
    notifyListeners();
  }

  void updateTargetLanguage(String value) {
    targetLanguage = value;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> saveApiKey(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _keyStore.delete();
      hasApiKey = false;
    } else {
      await _keyStore.write(normalized);
      hasApiKey = true;
    }
    errorMessage = null;
    notifyListeners();
  }

  Future<void> translate() async {
    final text = sourceText.trim();
    if (text.isEmpty) {
      errorMessage = '请输入要翻译的文本';
      notifyListeners();
      return;
    }

    String? apiKey;
    try {
      apiKey = await _keyStore.read();
    } on Object {
      errorMessage = '无法访问系统安全存储';
      notifyListeners();
      return;
    }
    if (apiKey == null || apiKey.trim().isEmpty) {
      hasApiKey = false;
      errorMessage = '请先配置 DeepL API Key';
      notifyListeners();
      return;
    }

    final requestVersion = ++_requestVersion;
    isTranslating = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _client.translate(
        apiKey: apiKey,
        text: sourceText,
        targetLanguage: targetLanguage,
      );
      if (requestVersion != _requestVersion) return;
      translatedText = result.text;
      detectedSourceLanguage = result.detectedSource;
    } on TranslationException catch (error) {
      if (requestVersion != _requestVersion) return;
      errorMessage = error.message;
    } on Object {
      if (requestVersion != _requestVersion) return;
      errorMessage = '翻译失败，请稍后重试';
    } finally {
      if (requestVersion == _requestVersion) {
        isTranslating = false;
        notifyListeners();
      }
    }
  }

  void cancel() {
    _requestVersion++;
    _client.cancel();
    isTranslating = false;
    notifyListeners();
  }

  void clear() {
    cancel();
    sourceText = '';
    translatedText = '';
    detectedSourceLanguage = null;
    errorMessage = null;
    notifyListeners();
  }

  void swap() {
    if (translatedText.isEmpty || detectedSourceLanguage == null) return;
    final previousSource = sourceText;
    final previousTarget = targetLanguage;
    sourceText = translatedText;
    translatedText = previousSource;
    targetLanguage = targetCodeForDetectedSource(detectedSourceLanguage!);
    detectedSourceLanguage = sourceCodeFor(previousTarget);
    errorMessage = null;
    notifyListeners();
  }
}
