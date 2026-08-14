import 'package:dev_orbit/features/json_formatter/json_transformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonTransformer', () {
    test('formats without changing large numbers or duplicate keys', () {
      const source = '{"id":123456789012345678901234567890,"dup":1,"dup":2}';

      final result = transformJson(source, JsonTransformMode.format, 2);

      expect(result.isValid, isTrue);
      expect(result.output, contains('123456789012345678901234567890'));
      expect(RegExp('"dup"').allMatches(result.output!).length, 2);
      expect(result.output, contains('\n  "id"'));
    });

    test('compacts whitespace but preserves string contents', () {
      const source = '{\n  "text": "a b \\\\ c",\n  "ok": true\n}';

      final result = transformJson(source, JsonTransformMode.compact, 2);

      expect(result.output, '{"text":"a b \\\\ c","ok":true}');
    });

    test('reports strict JSON errors with a location', () {
      const source = '{\n  "value": 1,\n}';

      final result = transformJson(source, JsonTransformMode.validate, 2);

      expect(result.isValid, isFalse);
      expect(result.issue?.line, greaterThanOrEqualTo(2));
      expect(result.issue?.column, greaterThanOrEqualTo(1));
    });

    test('repairs common non-standard JSON before formatting', () {
      const source = '''{
  name: 'DevOrbit'
  enabled: true,
  items: [1, 2,], // trailing comma and comment
}''';

      final result = transformJson(source, JsonTransformMode.format, 2);

      expect(result.isValid, isTrue);
      expect(result.output, '''{
  "name": "DevOrbit",
  "enabled": true,
  "items": [
    1,
    2
  ]
}''');
    });

    test('repairs newline-delimited JSON as an array', () {
      const source = '{"id":1}\n{"id":2}';

      final result = transformJson(source, JsonTransformMode.compact, 2);

      expect(result.isValid, isTrue);
      expect(result.output, '[{"id":1},{"id":2}]');
    });

    test('rejects scalar JSON roots even though the JSON spec allows them', () {
      for (final source in ['123', 'true', 'null', '"text"']) {
        final result = transformJson(source, JsonTransformMode.validate, 2);

        expect(result.isValid, isFalse, reason: source);
        expect(result.issue?.message, 'JSON 顶层必须是对象或数组');
      }
    });

    test('keeps arrays as valid top-level JSON documents', () {
      final result = transformJson('[1,2,3]', JsonTransformMode.format, 2);

      expect(result.isValid, isTrue);
      expect(result.output, '[\n  1,\n  2,\n  3\n]');
    });

    test('formats key-value members without adding a missing outer brace', () {
      const source = '''"name":"DevOrbit","items":[1,2]}''';

      final result = transformJson(source, JsonTransformMode.format, 2);

      expect(result.isValid, isFalse);
      expect(result.issue, isNotNull);
      expect(result.output, '''"name": "DevOrbit",
"items": [
  1,
  2
]
}''');
      expect(result.output, isNot(startsWith('{')));
    });

    test('formats JSON containers inside otherwise invalid text', () {
      const source = '''接口返回内容：
{"id":1,"detail":{"enabled":true}}
后续说明不是 JSON''';

      final result = transformJson(source, JsonTransformMode.format, 2);

      expect(result.isValid, isFalse);
      expect(result.issue, isNotNull);
      expect(result.output, '''接口返回内容：
{
  "id": 1,
  "detail": {
    "enabled": true
  }
}
后续说明不是 JSON''');
    });

    test('best-effort formats a container that cannot be fully repaired', () {
      const source = '{"valid":1,"broken":"\\uZZZZ","tail":[1,2]}';

      final result = transformJson(source, JsonTransformMode.format, 2);

      expect(result.isValid, isFalse);
      expect(result.output, contains('\n  "valid": 1,'));
      expect(result.output, contains('\n  "tail": ['));
    });

    test('keeps empty containers on one line', () {
      const source = '{"object":{},"array":[]}';

      final result = transformJson(source, JsonTransformMode.format, 4);

      expect(result.output, contains('"object": {}'));
      expect(result.output, contains('"array": []'));
    });
  });
}
