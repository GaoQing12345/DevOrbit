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

    test('keeps empty containers on one line', () {
      const source = '{"object":{},"array":[]}';

      final result = transformJson(source, JsonTransformMode.format, 4);

      expect(result.output, contains('"object": {}'));
      expect(result.output, contains('"array": []'));
    });
  });
}
