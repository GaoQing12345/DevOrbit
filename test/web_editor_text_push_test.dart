import 'package:dev_orbit/core/desktop/web_text_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a document the DOM already reported is not pushed back', () {
    // Every keystroke reaches Dart through `editorChanged` first, so echoing the
    // mirrored text would re-serialize the whole buffer for nothing.
    expect(webEditorTextPush(text: '{"a":1}', domText: '{"a":1}'), isNull);
  });

  test('an external rewrite is pushed in full', () {
    expect(webEditorTextPush(text: '{"a": 1}', domText: '{"a":1}'), '{"a": 1}');
  });

  test('the first sync after a reload always carries the document', () {
    expect(webEditorTextPush(text: '', domText: null), '');
    expect(webEditorTextPush(text: 'hello', domText: null), 'hello');
  });
}
