import 'package:dev_orbit/core/desktop/desktop_clipboard_focus_restorer.dart';
import 'package:dev_orbit/core/desktop/desktop_clipboard_reader.dart';
import 'package:dev_orbit/core/desktop/web_text_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/json_formatter_fixture.dart';

/// Regression coverage for the desktop rule: exactly one surface owns the caret
/// and the paste destination. A Flutter overlay field (a find input) and a
/// WebView editor must never both hold it.
void main() {
  Future<_OwnershipFixture> pumpOwnershipFixture(WidgetTester tester) async {
    final queryController = TextEditingController(text: 'needle');
    final queryFocusNode = FocusNode();
    final editorController = DesktopWebTextEditorController();
    final restorer = DesktopClipboardFocusRestorer(
      targets: [
        TextEditingClipboardTarget(
          controller: queryController,
          focusNode: queryFocusNode,
        ),
      ],
    );
    addTearDown(() {
      restorer.dispose();
      queryController.dispose();
      queryFocusNode.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                key: const ValueKey('query-field'),
                controller: queryController,
                focusNode: queryFocusNode,
              ),
              DesktopWebTextEditor(
                controller: editorController,
                text: '',
                onChanged: (_) {},
                debugLabel: 'ownership-editor',
              ),
            ],
          ),
        ),
      ),
    );
    restorer.active = true;
    return _OwnershipFixture(
      restorer: restorer,
      queryController: queryController,
      queryFocusNode: queryFocusNode,
      editorController: editorController,
    );
  }

  testWidgets('editor activation takes the caret away from the query field', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await pumpOwnershipFixture(tester);

    fixture.queryFocusNode.requestFocus();
    await tester.pump();
    expect(fixture.queryFocusNode.hasFocus, isTrue);

    // Opening find hands ownership to the overlay field and hides the caret.
    DesktopWebTextEditor.suspendActiveEditorFocus();
    await tester.pump();
    expect(DesktopWebTextEditor.debugActiveEditorSession, isFalse);

    // A click inside the WebView only reaches Flutter through the DOM bridge.
    fixture.editorController.debugHandleEditorActivation();
    await tester.pump();

    expect(fixture.queryFocusNode.hasFocus, isFalse);
    expect(DesktopWebTextEditor.debugActiveEditorLabel, 'ownership-editor');
    expect(DesktopWebTextEditor.debugActiveEditorSession, isTrue);
    expect(fixture.restorer.shouldReleaseTargetOnFocusExit, isTrue);
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'editor ownership keeps a captured paste out of the query field',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = await pumpOwnershipFixture(tester);

      fixture.queryFocusNode.requestFocus();
      await tester.pump();
      // The editor takes the session back while the overlay field still holds
      // Flutter focus. Restoring the caret must release that field as well.
      fixture.editorController.restoreFocus();
      await tester.pump();
      expect(DesktopWebTextEditor.editorOwnsEditingSession, isTrue);

      // The macOS runner captured Command+V and delivered the text natively.
      DesktopClipboardReader.debugDeliverPasteRequest(text: 'captured-text');
      await tester.pump(const Duration(milliseconds: 80));

      expect(fixture.queryController.text, 'needle');
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a captured paste is never dropped when no target claims it', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            key: const ValueKey('unregistered-field'),
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    DesktopClipboardReader.debugDeliverPasteRequest(text: 'rescued');
    await tester.pump();

    expect(controller.text, 'rescued');
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

class _OwnershipFixture {
  const _OwnershipFixture({
    required this.restorer,
    required this.queryController,
    required this.queryFocusNode,
    required this.editorController,
  });

  final DesktopClipboardFocusRestorer restorer;
  final TextEditingController queryController;
  final FocusNode queryFocusNode;
  final DesktopWebTextEditorController editorController;
}
