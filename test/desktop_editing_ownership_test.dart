import 'package:dev_orbit/core/desktop/desktop_clipboard_focus_restorer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/json_formatter_fixture.dart';

/// Regression coverage for the desktop rule: exactly one surface owns the caret
/// and the paste destination. A Flutter overlay field (a find input) and a
/// WebView editor must never both hold it.
void main() {
  testWidgets('Command+V does not revive the previously focused field', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TextEditingController(text: 'query');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final restorer = DesktopClipboardFocusRestorer(
      targets: [
        TextEditingClipboardTarget(
          controller: controller,
          focusNode: focusNode,
        ),
      ],
    );
    addTearDown(restorer.dispose);
    restorer.active = true;
    mockClipboard(tester, initialText: 'stale-paste');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                key: const ValueKey('query-field'),
                controller: controller,
                focusNode: focusNode,
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    // The user moves on to another surface inside the window. The field must
    // not stay a paste destination just because it was focused before.
    focusNode.unfocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 80));

    expect(controller.text, 'query');
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('closing the find panel releases its query field', (
    tester,
  ) async {
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('json-find-input')),
        matching: find.byType(TextField),
      ),
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('json-find-input')),
        matching: find.byType(EditableText),
      ),
      'needle',
    );
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();

    expect(field.focusNode!.hasFocus, isFalse);
    await disposeEditor(tester);
  });
}
