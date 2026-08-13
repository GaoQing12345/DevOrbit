import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class TranslationResult {
  const TranslationResult({required this.text, required this.detectedSource});

  final String text;
  final String detectedSource;
}

abstract interface class TranslationClient {
  Future<TranslationResult> translate({
    required String apiKey,
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  });

  void cancel();
}

class TranslationException implements Exception {
  const TranslationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DeepLTranslationClient implements TranslationClient {
  DeepLTranslationClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static final _endpoint = Uri.parse('https://api-free.deepl.com/v2/translate');

  final http.Client _httpClient;
  Completer<void>? _abortCompleter;

  @override
  void cancel() {
    final abortCompleter = _abortCompleter;
    if (abortCompleter != null && !abortCompleter.isCompleted) {
      abortCompleter.complete();
    }
  }

  @override
  Future<TranslationResult> translate({
    required String apiKey,
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final body = <String, Object>{
      'text': [text],
      'target_lang': targetLanguage,
      'preserve_formatting': true,
    };
    if (sourceLanguage != null) body['source_lang'] = sourceLanguage;

    cancel();
    final abortCompleter = Completer<void>();
    _abortCompleter = abortCompleter;
    final request =
        http.AbortableRequest(
            'POST',
            _endpoint,
            abortTrigger: abortCompleter.future,
          )
          ..headers.addAll({
            HttpHeaders.authorizationHeader: 'DeepL-Auth-Key $apiKey',
            HttpHeaders.contentTypeHeader: 'application/json',
          })
          ..body = jsonEncode(body);

    late final http.Response response;
    try {
      response = await _httpClient
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      if (!abortCompleter.isCompleted) abortCompleter.complete();
      throw const TranslationException('请求超时，请稍后重试');
    } on http.RequestAbortedException {
      throw const TranslationException('翻译已取消');
    } on http.ClientException {
      throw const TranslationException('无法连接 DeepL，请检查网络');
    } on SocketException {
      throw const TranslationException('无法连接 DeepL，请检查网络');
    } finally {
      if (identical(_abortCompleter, abortCompleter)) {
        _abortCompleter = null;
      }
    }

    if (response.statusCode != 200) {
      throw TranslationException(_messageForStatus(response.statusCode));
    }

    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final translations = payload['translations'] as List<dynamic>;
      final translation = translations.first as Map<String, dynamic>;
      return TranslationResult(
        text: translation['text'] as String,
        detectedSource: translation['detected_source_language'] as String,
      );
    } on Object {
      throw const TranslationException('DeepL 返回了无法识别的结果');
    }
  }

  String _messageForStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return '文本或语言选项无效';
      case 403:
        return 'API Key 无效，请重新配置';
      case 413:
        return '文本过长，请分段翻译';
      case 429:
        return '请求过于频繁，请稍后重试';
      case 456:
        return '本月免费额度已用完';
      default:
        return statusCode >= 500 ? 'DeepL 服务暂时不可用' : '翻译失败（$statusCode）';
    }
  }
}
