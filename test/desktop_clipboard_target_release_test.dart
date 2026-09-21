import 'package:dev_orbit/core/desktop/desktop_clipboard_focus_restorer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('cleared clipboard target cannot receive a later paste', (
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
    mockClipboard(tester, initialText: 'must not enter query');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(controller: controller, focusNode: focusNode),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    restorer.clearActiveTarget();
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
}
