import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('window focus restores the JSON editor before automatic paste', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: '{"from":"clipboard-panel"}');

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    await sendWindowEvent('blur');
    editor.focusNode!.unfocus();
    await tester.pump();

    await sendWindowEvent('focus');
    await pasteWithMeta(tester);
    await tester.pump();

    expect(editor.focusNode!.hasFocus, isTrue);
    expect(fixture.controller.text, '{"from":"clipboard-panel"}');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('window focus restores the find input before automatic paste', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: 'clipboard-panel-keyword');

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('json-find-input')),
        matching: find.byType(TextField),
      ),
    );
    await sendWindowEvent('blur');
    field.focusNode!.unfocus();
    await tester.pump();

    await sendWindowEvent('focus');
    await pasteWithMeta(tester);
    await tester.pump();

    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'clipboard-panel-keyword');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Command+V pastes the focused target without window events', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create(text: 'abcdef');
    mockClipboard(tester, initialText: 'direct-command-v');
    final nativeClipboard = mockClipboardRevision(tester);
    nativeClipboard.pasteCapturePrearmed = false;
    await tester.pumpWidget(fixture.widget);

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );
    editor.focusNode!.requestFocus();
    await tester.pump();

    await pasteWithMeta(tester);
    await tester.pump(const Duration(milliseconds: 80));

    expect(fixture.controller.text, 'abcdirect-command-vdef');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('find paste survives a delayed window focus event', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: 'paste-before-focus');

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('json-find-input')),
        matching: find.byType(TextField),
      ),
    );
    await sendWindowEvent('blur');
    field.focusNode!.unfocus();
    await tester.pump();

    await pasteWithMeta(tester);
    await sendWindowEvent('focus');
    await tester.pump();

    expect(field.controller!.text, 'paste-before-focus');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('find focus exit releases stale paste ownership', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: 'must not enter query');

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

    field.focusNode!.unfocus();
    await tester.pump();
    await pasteWithMeta(tester);
    await tester.pump(const Duration(milliseconds: 80));

    expect(field.controller!.text, 'needle');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('automatic paste survives a delayed focus event', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: '{"paste":"macOS-panel"}');

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    await sendWindowEvent('blur');
    editor.focusNode!.unfocus();
    await tester.pump();

    await pasteWithMeta(tester);
    await sendWindowEvent('focus');
    await tester.pump();
    await tester.pump();

    expect(fixture.controller.text, '{"paste":"macOS-panel"}');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> pasteWithMeta(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
}

Future<void> sendWindowEvent(String eventName) async {
  windowManager.hasListeners;
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('onEvent', {'eventName': eventName}),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('window_manager', message, (_) {});
}
