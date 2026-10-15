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
      expect(result.issue?.line, 3);
      expect(result.issue?.column, 1);
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

    test('accepts scalar JSON roots', () {
      for (final source in ['123', 'true', 'null', '"text"']) {
        final result = transformJson(source, JsonTransformMode.validate, 2);

        expect(result.isValid, isTrue, reason: source);
      }
      expect(
        transformJson('"text"', JsonTransformMode.format, 2).output,
        '"text"',
      );
      expect(transformJson('123', JsonTransformMode.format, 2).output, '123');
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

    test('flags content that only passed after an automatic repair', () {
      final repaired = transformJson(
        '{name:"DevOrbit"}',
        JsonTransformMode.format,
        2,
      );
      final clean = transformJson(
        '{"name":"DevOrbit"}',
        JsonTransformMode.format,
        2,
      );

      expect(repaired.isValid, isTrue);
      expect(repaired.repaired, isTrue);
      expect(clean.repaired, isFalse);
    });

    test('indents with tabs when asked', () {
      final result = transformJson(
        '{"a":[1]}',
        JsonTransformMode.format,
        2,
        useTabs: true,
      );

      expect(result.output, '{\n\t"a": [\n\t\t1\n\t]\n}');
    });

    group('member sorting', () {
      test('sorts keys while keeping numbers and duplicates verbatim', () {
        const source =
            '{"b":1e5,"a":123456789012345678901234567890,"dup":1,"dup":2}';

        final result = transformJson(source, JsonTransformMode.sort, 2);

        expect(result.isValid, isTrue);
        expect(result.output, '''{
  "a": 123456789012345678901234567890,
  "b": 1e5,
  "dup": 1,
  "dup": 2
}''');
      });

      test('sorts nested objects but leaves array order alone', () {
        const source = '{"b":{"d":1,"c":2},"a":[{"z":1,"y":2},"x"]}';

        final result = transformJson(source, JsonTransformMode.sort, 2);

        expect(result.output, '''{
  "a": [
    {
      "y": 2,
      "z": 1
    },
    "x"
  ],
  "b": {
    "c": 2,
    "d": 1
  }
}''');
      });

      test('sorts escaped keys by their decoded text', () {
        final result = transformJson(
          '{"b":1,"\\u0061":2}',
          JsonTransformMode.sort,
          2,
        );

        expect(result.output, '{\n  "\\u0061": 2,\n  "b": 1\n}');
      });
    });

    group('error messages', () {
      String messageFor(String source) {
        final result = transformJson(source, JsonTransformMode.validate, 2);
        return result.issue?.message ?? '';
      }

      test('names a trailing comma', () {
        expect(messageFor('{\n  "value": 1,\n}'), contains('尾随逗号'));
      });

      test('asks for quotes around a bare key', () {
        expect(messageFor('{a:1}'), contains('双引号'));
      });

      test('reports the container left open at the end', () {
        expect(messageFor('{"a":1'), contains('缺少结尾'));
        expect(messageFor('[1,2'), contains('“]”'));
      });

      test('reports an unterminated string', () {
        expect(messageFor('{"a":"x'), contains('没有闭合'));
      });

      test('reports trailing content after the document', () {
        expect(messageFor('{"a":1}extra'), contains('多余内容'));
      });

      test('separates a missing comma from a missing colon', () {
        expect(messageFor('{"a":1 "b":2}'), contains('缺少一个逗号'));
        expect(messageFor('{"a" 1}'), contains('缺少冒号'));
      });

      test('reports a missing value after a colon', () {
        expect(messageFor('{"a":}'), contains('冒号后面缺少值'));
      });

      test('reports malformed numbers', () {
        expect(messageFor('{"a":+1}'), contains('“+”'));
        expect(messageFor('{"a":01}'), contains('前导 0'));
      });

      test('counts columns in code points so emoji line up', () {
        final result = transformJson(
          '{"😀":1,}',
          JsonTransformMode.validate,
          2,
        );

        expect(result.issue?.line, 1);
        expect(result.issue?.column, 8);
      });
    });

    group('escaping', () {
      test('escapes a document into a string literal', () {
        expect(escapeJson('{"a":1}'), '"{\\"a\\":1}"');
      });

      test('unescapes bare escaped text', () {
        expect(unescapeJson('{\\"a\\":1}'), '{"a":1}');
        expect(unescapeJson('a\\nb\\tc'), 'a\nb\tc');
      });

      test('unescapes a whole quoted literal', () {
        expect(unescapeJson('"{\\"a\\":1}"'), '{"a":1}');
        expect(unescapeJson('"\\u4f60\\u597d"'), '你好');
      });

      test('keeps unknown escapes untouched', () {
        expect(unescapeJson('a\\qb'), 'a\\qb');
      });
    });
  });
}
