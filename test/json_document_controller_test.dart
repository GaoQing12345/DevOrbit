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
}
