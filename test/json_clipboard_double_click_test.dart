import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('clipboard double-click inserts at the previous editor cursor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create(text: 'abcdef');
    final clipboard = mockClipboard(tester, initialText: 'old clipboard');
    final revision = mockClipboardRevision(tester);
    await tester.pumpWidget(fixture.widget);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );
    editor.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump();

    await sendWindowEvent('blur');
    await tester.pump();
    editor.focusNode!.unfocus();
    clipboard.text = '-inserted-';
    revision.pendingPasteText = '-inserted-';
    revision.revision++;
    await sendWindowEvent('focus');
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(fixture.controller.text, 'abc-inserted-def');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('clipboard double-click inserts at the previous find cursor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    final clipboard = mockClipboard(tester, initialText: 'old clipboard');
    final revision = mockClipboardRevision(tester);
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
    await tester.pump();
    await tester.pump();

    await sendWindowEvent('blur');
    await tester.pump();
    field.focusNode!.unfocus();
    clipboard.text = 'XX';
    revision.pendingPasteText = 'XX';
    revision.revision++;
    await sendWindowEvent('focus');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(field.controller!.text, 'abXXcd');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('clipboard revision pastes an item with unchanged text', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create(text: 'abcdef');
    mockClipboard(tester, initialText: 'same');
    final revision = mockClipboardRevision(tester);
    await tester.pumpWidget(fixture.widget);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );
    editor.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump();

    await sendWindowEvent('blur');
    await tester.pump();
    editor.focusNode!.unfocus();
    revision.pendingPasteText = 'same';
    revision.revision++;
    await sendWindowEvent('focus');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(fixture.controller.text, 'abcsamedef');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('clipboard double-click inserts at the previous replace cursor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    final clipboard = mockClipboard(tester, initialText: 'old clipboard');
    final revision = mockClipboardRevision(tester);
    await tester.pumpWidget(fixture.widget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('json-replace-input')),
        matching: find.byType(TextField),
      ),
    );
    field.controller!.value = const TextEditingValue(
      text: 'abcd',
      selection: TextSelection.collapsed(offset: 2),
    );
    field.focusNode!.requestFocus();
    await tester.pump();

    await sendWindowEvent('blur');
    await tester.pump();
    field.focusNode!.unfocus();
    clipboard.text = 'YY';
    revision.pendingPasteText = 'YY';
    revision.revision++;
    await sendWindowEvent('focus');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(field.controller!.text, 'abYYcd');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('system paste after focus is not duplicated', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create(text: 'abcdef');
    final clipboard = mockClipboard(tester, initialText: 'old clipboard');
    final revision = mockClipboardRevision(tester);
    await tester.pumpWidget(fixture.widget);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );

    await sendWindowEvent('blur');
    await tester.pump();
    editor.focusNode!.unfocus();
    clipboard.text = 'X';
    revision.pendingPasteText = 'X';
    revision.revision++;
    await sendWindowEvent('focus');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 200));

    expect(fixture.controller.text, 'abcXdef');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('window switching without clipboard change does not paste', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create(text: 'abcdef');
    mockClipboard(tester, initialText: 'unchanged');
    mockClipboardRevision(tester);
    await tester.pumpWidget(fixture.widget);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );

    await sendWindowEvent('blur');
    await tester.pump();
    editor.focusNode!.unfocus();
    await sendWindowEvent('focus');
    await tester.pump(const Duration(milliseconds: 200));

    expect(fixture.controller.text, 'abcdef');
    expect(editor.controller!.selection.extentOffset, 3);
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> pasteWithMeta(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
}

Future<void> pasteWithControl(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

Future<void> sendWindowEvent(String eventName) async {
  windowManager.hasListeners;
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('onEvent', {'eventName': eventName}),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('window_manager', message, (_) {});
}
