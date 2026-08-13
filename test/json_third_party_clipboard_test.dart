import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('iCopy paste uses text captured before clipboard restoration', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create(text: 'abcdef');
    mockClipboard(tester, initialText: 'restored clipboard');
    final nativeClipboard = mockClipboardRevision(tester);
    await tester.pumpWidget(fixture.widget);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );

    await _blurEditor(tester, editor.focusNode!);
    nativeClipboard.pendingPasteText = 'iCopy item';
    await _focusWindow(tester);
    await _pasteWithMeta(tester);

    expect(fixture.controller.text, 'abciCopy itemdef');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'QuickClipboard paste uses text captured before clipboard restoration',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = await JsonFormatterFixture.create(text: 'abcdef');
      mockClipboard(tester, initialText: 'restored clipboard');
      final nativeClipboard = mockClipboardRevision(tester);
      await tester.pumpWidget(fixture.widget);
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      editor.controller!.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );

      await _blurEditor(tester, editor.focusNode!);
      nativeClipboard.pendingPasteText = 'QuickClipboard item';
      await _focusWindow(tester);
      await _pasteWithControl(tester);

      expect(fixture.controller.text, 'abcQuickClipboard itemdef');
      await tester.pump(const Duration(milliseconds: 350));
      await disposeEditor(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('QuickClipboard paste restores the previous find cursor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    mockClipboard(tester, initialText: 'restored clipboard');
    final nativeClipboard = mockClipboardRevision(tester);
    await tester.pumpWidget(fixture.widget);
    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('json-find-input')),
        matching: find.byType(TextField),
      ),
    );
    field.controller!.value = const TextEditingValue(
      text: 'abcd',
      selection: TextSelection.collapsed(offset: 2),
    );

    await _blurEditor(tester, field.focusNode!);
    nativeClipboard.pendingPasteText = 'QuickClipboard item';
    await _focusWindow(tester);
    await _pasteWithControl(tester);

    expect(field.controller!.text, 'abQuickClipboard itemcd');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _blurEditor(WidgetTester tester, FocusNode focusNode) async {
  focusNode.requestFocus();
  await tester.pump();
  await _sendWindowEvent('blur');
  focusNode.unfocus();
  await tester.pump();
}

Future<void> _focusWindow(WidgetTester tester) async {
  await _sendWindowEvent('focus');
  await tester.pump();
}

Future<void> _pasteWithMeta(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<void> _pasteWithControl(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _sendWindowEvent(String eventName) async {
  windowManager.hasListeners;
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('onEvent', {'eventName': eventName}),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('window_manager', message, (_) {});
}
