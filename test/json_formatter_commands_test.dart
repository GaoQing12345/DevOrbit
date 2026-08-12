import 'package:dev_orbit/features/json_formatter/json_highlight_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('Control+V pastes clipboard text into the find input', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: 'clipboard-keyword');

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('json-find-input')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('json-find-input')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, 'clipboard-keyword');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Command+V pastes clipboard text into the find input on macOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: 'mac-clipboard-keyword');

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('json-find-input')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('json-find-input')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, 'mac-clipboard-keyword');
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('find input restores focus after the clipboard panel closes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: 'restored-clipboard');

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    final fieldFinder = find.descendant(
      of: find.byKey(const ValueKey('json-find-input')),
      matching: find.byType(TextField),
    );
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.focusNode!.hasFocus, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    field.focusNode!.unfocus();
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    expect(editor.focusNode!.hasFocus, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'restored-clipboard');

    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('JSON editor restores focus after the clipboard panel closes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: '{"from":"clipboard"}');

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    expect(editor.focusNode!.hasFocus, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    editor.focusNode!.unfocus();
    await tester.pump();
    expect(editor.focusNode!.hasFocus, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    expect(editor.focusNode!.hasFocus, isTrue);
    expect(fixture.controller.text, '{"from":"clipboard"}');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows+V remains available to clipboard history', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: '{"source":"history"}');

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(fixture.controller.text, isEmpty);
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('JSON editor restores focus and accepts Command+V on macOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);
    mockClipboard(tester, initialText: '{"platform":"macOS"}');

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.focusNode!.requestFocus();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    editor.focusNode!.unfocus();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump();

    expect(editor.focusNode!.hasFocus, isTrue);
    expect(fixture.controller.text, '{"platform":"macOS"}');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('compact action copies the compact JSON', (tester) async {
    final fixture = await JsonFormatterFixture.create(
      text: '{\n  "value": 1\n}',
    );
    await tester.pumpWidget(fixture.widget);
    final clipboard = mockClipboard(tester);

    await tester.tap(find.byTooltip('压缩并复制'));
    await waitForControllerText(tester, fixture.controller, '{"value":1}');

    expect(fixture.controller.text, '{"value":1}');
    expect(clipboard.text, '{"value":1}');
    expect(fixture.controller.isDirty, isFalse);
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
  });

  testWidgets('toolbar collapses and expands every JSON level', (tester) async {
    const nestedJson = '''{
  "profile": {
    "items": [
      {
        "id": 1
      }
    ]
  }
}''';
    final fixture = await JsonFormatterFixture.create(text: nestedJson);
    await tester.pumpWidget(fixture.widget);
    await waitForFoldChunks(tester, 4);

    await tester.tap(find.byTooltip('折叠全部'));
    await tester.pump();

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.controller!.codeLines.length, 2);
    expect(editor.controller!.codeLines.first.chunkParent, isTrue);

    await tester.tap(find.byTooltip('展开全部'));
    await tester.pump();

    expect(editor.controller!.codeLines.length, 9);
    expect(
      List.generate(
        editor.controller!.codeLines.length,
        (index) => index,
      ).where((index) => editor.controller!.codeLines[index].chunkParent),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
  });

  testWidgets('modern toolbar fits the minimum desktop window', (tester) async {
    tester.view.physicalSize = const Size(720, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = await JsonFormatterFixture.create();

    await tester.pumpWidget(fixture.widget);

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('折叠全部'), findsOneWidget);
    expect(find.byTooltip('展开全部'), findsOneWidget);
    await disposeEditor(tester);
  });

  test('light JSON highlight color uses A31515', () {
    expect(jsonAtomOneLightTheme['number']?.color, const Color(0xFFA31515));
    expect(jsonAtomOneLightTheme['attr']?.color, const Color(0xFFA31515));
  });
}
