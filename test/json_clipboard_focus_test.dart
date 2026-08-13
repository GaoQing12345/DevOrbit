import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('window focus restores the JSON editor before automatic paste', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
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
    await pasteWithControl(tester);
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
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
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
    await pasteWithControl(tester);
    await tester.pump();

    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'clipboard-panel-keyword');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('automatic paste survives a delayed window focus event', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: '{"paste":"before-focus-event"}');

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    await sendWindowEvent('blur');
    editor.focusNode!.unfocus();
    await tester.pump();

    await pasteWithControl(tester);
    await sendWindowEvent('focus');
    await tester.pump();
    await tester.pump();

    expect(fixture.controller.text, '{"paste":"before-focus-event"}');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows+V arms paste when no window events are emitted', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: '{"paste":"after-Windows-V"}');

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    await pasteWithMeta(tester);
    editor.focusNode!.unfocus();
    await tester.pump();

    await pasteWithControl(tester);
    await tester.pump();
    await tester.pump();

    expect(editor.focusNode!.hasFocus, isTrue);
    expect(fixture.controller.text, '{"paste":"after-Windows-V"}');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('find paste survives a delayed window focus event', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
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

    await pasteWithControl(tester);
    await sendWindowEvent('focus');
    await tester.pump();

    expect(field.controller!.text, 'paste-before-focus');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows+V arms find paste without window events', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: 'after-Windows-V');

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('json-find-input')),
        matching: find.byType(TextField),
      ),
    );
    await pasteWithMeta(tester);
    field.focusNode!.unfocus();
    await tester.pump();

    await pasteWithControl(tester);
    await tester.pump();

    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'after-Windows-V');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows+V stays available while focus restoration is pending', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: '{"must":"not-paste"}');

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    await sendWindowEvent('blur');
    editor.focusNode!.unfocus();
    await tester.pump();

    await pasteWithMeta(tester);
    await sendWindowEvent('focus');
    await tester.pump();

    expect(fixture.controller.text, isEmpty);
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows+V in another input does not arm JSON paste', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final otherController = TextEditingController();
    addTearDown(otherController.dispose);
    final fixture = await JsonFormatterFixture.create(
      sibling: TextField(
        key: const ValueKey('other-input'),
        controller: otherController,
      ),
      showSibling: true,
    );
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: 'other-input-text');

    await tester.tap(find.byKey(const ValueKey('other-input')));
    await tester.pump();

    await pasteWithMeta(tester);
    await pasteWithControl(tester);
    await tester.pump();
    await tester.pump();

    expect(fixture.controller.text, isEmpty);
    expect(otherController.text, 'other-input-text');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS automatic paste survives a delayed focus event', (
    tester,
  ) async {
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

Future<void> pasteWithControl(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
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
