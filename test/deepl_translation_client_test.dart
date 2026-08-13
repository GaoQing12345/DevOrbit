import 'dart:convert';

import 'package:dev_orbit/features/translator/deepl_translation_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sends translation request to the DeepL Free endpoint', () async {
    late http.Request captured;
    final client = DeepLTranslationClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'translations': [
              {'detected_source_language': 'EN', 'text': '你好'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await client.translate(
      apiKey: 'test-key',
      text: 'Hello',
      targetLanguage: 'ZH-HANS',
    );

    expect(captured.url.host, 'api-free.deepl.com');
    expect(captured.headers['authorization'], 'DeepL-Auth-Key test-key');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['text'], ['Hello']);
    expect(body['target_lang'], 'ZH-HANS');
    expect(body['preserve_formatting'], isTrue);
    expect(body.containsKey('source_lang'), isFalse);
    expect(result.text, '你好');
    expect(result.detectedSource, 'EN');
  });

  test('maps exhausted quota to a readable error', () async {
    final client = DeepLTranslationClient(
      httpClient: MockClient((_) async => http.Response('{}', 456)),
    );

    expect(
      () => client.translate(
        apiKey: 'test-key',
        text: 'Hello',
        targetLanguage: 'ZH-HANS',
      ),
      throwsA(
        isA<TranslationException>().having(
          (error) => error.message,
          'message',
          '本月免费额度已用完',
        ),
      ),
    );
  });
}
