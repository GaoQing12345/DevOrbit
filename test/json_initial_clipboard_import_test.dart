import 'package:dev_orbit/features/json_formatter/json_document_controller.dart';
import 'package:dev_orbit/features/json_formatter/json_initial_clipboard_import.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial clipboard JSON is formatted before editing starts', () async {
    final controller = JsonDocumentController();

    final imported = await importInitialClipboardJson(
      controller: controller,
      indentSize: 2,
      readClipboard: () async => const ClipboardData(text: '{"value":1}'),
    );

    expect(imported, isTrue);
    expect(controller.text, '{\n  "value": 1\n}');
    expect(controller.isDirty, isFalse);
  });

  test('invalid initial clipboard text leaves the document blank', () async {
    final controller = JsonDocumentController();

    final imported = await importInitialClipboardJson(
      controller: controller,
      indentSize: 2,
      readClipboard: () async => const ClipboardData(text: 'not json'),
    );

    expect(imported, isFalse);
    expect(controller.text, isEmpty);
  });
}
