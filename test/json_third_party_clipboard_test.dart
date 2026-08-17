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
    final sessionId = nativeClipboard.armedSessionId!;
    nativeClipboard.pendingPasteText = 'iCopy item';
    await _focusWindow(tester);
    await _sendNativePasteRequested(sessionId);
    await tester.pump();

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

  testWidgets(
    'QuickClipboard double-click uses the first native clipboard update',
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
      nativeClipboard.revision += 2;
      await _focusWindow(tester);
      await _pasteWithControl(tester);

      expect(fixture.controller.text, 'abcQuickClipboard itemdef');
      await tester.pump(const Duration(milliseconds: 350));
      await disposeEditor(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('clipboard changes do not insert without a paste action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create(text: 'abcdef');
    mockClipboard(tester, initialText: 'copied text');
    final nativeClipboard = mockClipboardRevision(tester);
    await tester.pumpWidget(fixture.widget);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );

    await _blurEditor(tester, editor.focusNode!);
    nativeClipboard.pendingPasteText = 'copied text';
    nativeClipboard.observedChange = true;
    await _focusWindow(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(fixture.controller.text, 'abcdef');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'QuickClipboard paste survives its delayed hide animation and native event',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = await JsonFormatterFixture.create(text: 'abcdef');
      mockClipboard(tester, initialText: 'old clipboard');
      final nativeClipboard = mockClipboardRevision(tester);
      await tester.pumpWidget(fixture.widget);
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      editor.controller!.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );

      await _blurEditor(tester, editor.focusNode!);
      final sessionId = nativeClipboard.armedSessionId!;
      await _focusWindow(tester);
      await tester.pump(const Duration(milliseconds: 260));

      nativeClipboard.pendingPasteText = 'delayed QuickClipboard item';
      nativeClipboard.observedChange = true;
      await _sendNativePasteRequested(sessionId);
      await tester.pump();

      expect(fixture.controller.text, 'abcdelayed QuickClipboard itemdef');
      await tester.pump(const Duration(milliseconds: 350));
      await disposeEditor(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'QuickClipboard Shift+Insert is suppressed after native insertion',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = await JsonFormatterFixture.create(text: 'abcdef');
      mockClipboard(tester, initialText: 'QuickClipboard item');
      final nativeClipboard = mockClipboardRevision(tester);
      await tester.pumpWidget(fixture.widget);
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      editor.controller!.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );

      await _blurEditor(tester, editor.focusNode!);
      final sessionId = nativeClipboard.armedSessionId!;
      await _focusWindow(tester);
      nativeClipboard.pendingPasteText = 'QuickClipboard item';
      nativeClipboard.observedChange = true;
      await _sendNativePasteRequested(sessionId);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.insert);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

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

  testWidgets(
    'automatic paste never falls back to a restored system clipboard value',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = await JsonFormatterFixture.create(text: 'abcdef');
      final clipboard = mockClipboard(tester, initialText: 'old clipboard');
      final nativeClipboard = mockClipboardRevision(tester);
      await tester.pumpWidget(fixture.widget);
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      editor.controller!.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );

      await _blurEditor(tester, editor.focusNode!);
      clipboard.text = 'restored old value';
      nativeClipboard.revision++;
      await _focusWindow(tester);
      await tester.pump(const Duration(milliseconds: 140));

      expect(fixture.controller.text, 'abcdef');
      await tester.pump(const Duration(milliseconds: 350));
      await disposeEditor(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'a missed native capture never pastes the restored previous value',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = await JsonFormatterFixture.create(text: 'abcdef');
      mockClipboard(tester, initialText: 'restored previous value');
      final nativeClipboard = mockClipboardRevision(tester);
      await tester.pumpWidget(fixture.widget);
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      editor.controller!.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 3,
      );

      await _blurEditor(tester, editor.focusNode!);
      nativeClipboard.observedChange = true;
      await _focusWindow(tester);
      await _pasteWithControl(tester);
      await tester.pump(const Duration(milliseconds: 80));

      expect(fixture.controller.text, 'abcdef');
      await tester.pump(const Duration(milliseconds: 350));
      await disposeEditor(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );
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

Future<void> _sendNativePasteRequested(int sessionId) async {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('pasteRequested', {'sessionId': sessionId}),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('dev_orbit/clipboard', message, (_) {});
}
