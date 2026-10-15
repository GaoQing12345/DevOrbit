import 'package:dev_orbit/features/json_formatter/json_document_controller.dart';
import 'package:dev_orbit/features/json_formatter/json_transformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('safe clipboard import formats a clean document', () async {
    final controller = JsonDocumentController();

    final imported = await controller.importClipboard('{"value":1}', 2);

    expect(imported, isTrue);
    expect(controller.text, '{\n  "value": 1\n}');
    expect(controller.isDirty, isFalse);
  });

  test('safe clipboard import repairs non-standard JSON', () async {
    final controller = JsonDocumentController();

    final imported = await controller.importClipboard("{name:'DevOrbit',}", 2);

    expect(imported, isTrue);
    expect(controller.text, '{\n  "name": "DevOrbit"\n}');
    expect(controller.isDirty, isFalse);
  });

  test(
    'clipboard import keeps partial formatting and reports the error',
    () async {
      final controller = JsonDocumentController();

      final imported = await controller.importClipboard(
        'before {"value":1,"items":[1,2]} after',
        2,
      );

      expect(imported, isTrue);
      expect(controller.text, contains('{\n  "value": 1,'));
      expect(controller.text, contains('\n  "items": ['));
      expect(controller.status, JsonDocumentStatus.invalid);
      expect(controller.issue, isNotNull);
    },
  );

  test(
    'clipboard import formats a missing opening brace without adding it',
    () async {
      final controller = JsonDocumentController();

      final imported = await controller.importClipboard(
        '"name":"DevOrbit","items":[1,2]}',
        2,
      );

      expect(imported, isTrue);
      expect(controller.text, isNot(startsWith('{')));
      expect(controller.text, contains('"name": "DevOrbit",\n'));
      expect(controller.text, contains('"items": [\n  1,\n  2\n]'));
      expect(controller.status, JsonDocumentStatus.invalid);
    },
  );

  test('safe clipboard import never replaces dirty content', () async {
    final controller = JsonDocumentController();
    controller.userEdit('{"draft":true}');

    final imported = await controller.importClipboard('{"value":1}', 2);

    expect(imported, isFalse);
    expect(controller.text, '{"draft":true}');
  });

  test('manual formatting marks the document dirty', () async {
    final controller = JsonDocumentController();
    await controller.loadText('{"value":1}');

    final transformed = await controller.transform(JsonTransformMode.format, 2);

    expect(transformed, isTrue);
    expect(controller.isDirty, isTrue);
    expect(controller.status, JsonDocumentStatus.valid);
  });

  test('clipboard import reports an oversized payload', () async {
    final controller = JsonDocumentController();

    final imported = await controller.importClipboard(
      'x' * (maxJsonBytes + 1),
      2,
    );

    expect(imported, isFalse);
    expect(controller.text, isEmpty);
    expect(controller.status, JsonDocumentStatus.invalid);
    expect(controller.issue?.message, contains('10 MiB'));
  });

  test('preview transform leaves the document alone', () async {
    final controller = JsonDocumentController();
    await controller.loadText('{\n  "value": 1\n}');

    final preview = await controller.previewTransform(
      JsonTransformMode.compact,
      2,
    );

    expect(preview?.output, '{"value":1}');
    expect(controller.text, '{\n  "value": 1\n}');
    expect(controller.isDirty, isFalse);
  });

  test('sorting keys keeps duplicate members and large numbers', () async {
    final controller = JsonDocumentController();
    await controller.loadText(
      '{"b":1e5,"a":123456789012345678901234567890,"dup":1,"dup":2}',
    );

    final sorted = await controller.transform(JsonTransformMode.sort, 2);

    expect(sorted, isTrue);
    expect(controller.text, '''{
  "a": 123456789012345678901234567890,
  "b": 1e5,
  "dup": 1,
  "dup": 2
}''');
  });

  test('escape and unescape round trip through the document', () async {
    final controller = JsonDocumentController();
    await controller.loadText('{"value":1}');

    await controller.escapeDocument();
    expect(controller.text, '"{\\"value\\":1}"');

    await controller.unescapeDocument();
    expect(controller.text, '{"value":1}');
  });

  test('formatting flags content that only passed after a repair', () async {
    final controller = JsonDocumentController();
    await controller.loadText('{name:"DevOrbit"}');

    // Validation alone reports the problem instead of silently repairing it.
    expect(controller.status, JsonDocumentStatus.invalid);
    expect(controller.repaired, isFalse);

    await controller.transform(JsonTransformMode.format, 2);

    expect(controller.text, '{\n  "name": "DevOrbit"\n}');
    expect(controller.status, JsonDocumentStatus.valid);
    expect(controller.repaired, isTrue);
  });

  test('clean content is never flagged as repaired', () async {
    final controller = JsonDocumentController();
    await controller.loadText('{"value":1}');

    await controller.transform(JsonTransformMode.format, 2);

    expect(controller.repaired, isFalse);
  });

  test('overlapping validation runs settle on the latest content', () async {
    final controller = JsonDocumentController();
    await controller.loadText('{"value":1}');

    await Future.wait([controller.validate(), controller.validate()]);

    expect(controller.isValidating, isFalse);
    expect(controller.status, JsonDocumentStatus.valid);
  });

  test('error offset maps the reported location back to the text', () async {
    final controller = JsonDocumentController();
    await controller.loadText('{\n  "value": 1,\n}');

    expect(controller.status, JsonDocumentStatus.invalid);
    final offset = controller.errorOffset();

    expect(offset, isNotNull);
    expect(controller.text.substring(offset!), startsWith('}'));
  });
}
