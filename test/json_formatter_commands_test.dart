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

  testWidgets('compress-and-copy leaves the editor content untouched', (
    tester,
  ) async {
    final fixture = await JsonFormatterFixture.create(
      text: '{\n  "value": 1\n}',
    );
    await tester.pumpWidget(fixture.widget);
    final clipboard = mockClipboard(tester);

    await tester.tap(find.byTooltip('压缩并复制（不改动编辑器内容）'));
    await waitForClipboardText(tester, clipboard, '{"value":1}');

    expect(fixture.controller.text, '{\n  "value": 1\n}');
    // Copying the compact form is not saving either.
    expect(fixture.controller.isDirty, isTrue);
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
  });

  testWidgets('compact rewrites the document in place and stays dirty', (
    tester,
  ) async {
    final fixture = await JsonFormatterFixture.create(
      text: '{\n  "value": 1\n}',
    );
    await tester.pumpWidget(fixture.widget);

    await tester.tap(find.byTooltip('压缩（原地）'));
    await waitForControllerText(tester, fixture.controller, '{"value":1}');

    expect(fixture.controller.text, '{"value":1}');
    expect(fixture.controller.isDirty, isTrue);
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
  });

  testWidgets('copy does not mark the document as saved', (tester) async {
    final fixture = await JsonFormatterFixture.create(text: '{"value":1}');
    await tester.pumpWidget(fixture.widget);
    final clipboard = mockClipboard(tester);

    await tester.tap(find.byTooltip('复制'));
    await waitForClipboardText(tester, clipboard, '{"value":1}');

    expect(fixture.controller.isDirty, isTrue);
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
  });

  testWidgets('more menu sorts every object by key', (tester) async {
    final fixture = await JsonFormatterFixture.create(
      text: '{"b":1,"a":{"d":1,"c":2}}',
    );
    await tester.pumpWidget(fixture.widget);

    await tapMoreMenuItem(tester, '按键名排序');
    await waitForControllerText(
      tester,
      fixture.controller,
      '{\n  "a": {\n    "c": 2,\n    "d": 1\n  },\n  "b": 1\n}',
    );

    expect(fixture.controller.text, contains('\n  "a": {'));
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
  });

  testWidgets('more menu escapes and unescapes the document', (tester) async {
    final fixture = await JsonFormatterFixture.create(text: '{"value":1}');
    await tester.pumpWidget(fixture.widget);

    await tapMoreMenuItem(tester, '转义为字符串');
    await waitForControllerText(
      tester,
      fixture.controller,
      '"{\\"value\\":1}"',
    );

    await tapMoreMenuItem(tester, '去转义');
    await waitForControllerText(tester, fixture.controller, '{"value":1}');
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
  });

  testWidgets('more menu validates and confirms a clean document', (
    tester,
  ) async {
    final fixture = await JsonFormatterFixture.create(text: '{"value":1}');
    await tester.pumpWidget(fixture.widget);

    await tapMoreMenuItem(tester, '校验 JSON');
    // The confirmation only appears when the menu action actually ran.
    await waitForTextContaining(tester, 'JSON 校验通过');
    expect(fixture.controller.issue, isNull);
    await disposeEditor(tester);
  });

  testWidgets('more menu validate reports the Chinese error message', (
    tester,
  ) async {
    final fixture = await JsonFormatterFixture.create(text: '{"value":1,}');
    await tester.pumpWidget(fixture.widget);

    await tapMoreMenuItem(tester, '校验 JSON');
    await waitForTextContaining(tester, '尾随逗号');
    await disposeEditor(tester);
  });

  testWidgets('clicking the status bar error jumps to the offending text', (
    tester,
  ) async {
    final fixture = await JsonFormatterFixture.create(text: '{\n  "v": 1,\n}');
    await tester.pumpWidget(fixture.widget);
    await waitForTextContaining(tester, '尾随逗号');

    await tester.tap(find.textContaining('尾随逗号'));
    await tester.pump();

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    final selection = editor.controller!.selection;
    expect(selection.baseIndex, 2);
    expect(selection.baseOffset, 0);
    await disposeEditor(tester);
  });

  testWidgets('find panel case toggle changes what matches', (tester) async {
    final fixture = await JsonFormatterFixture.create(
      text: '{"abc":1,"ABC":2}',
    );
    await tester.pumpWidget(fixture.widget);

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('json-find-input')),
      'abc',
    );
    // Case is ignored by default, so both keys match.
    await waitForText(tester, '1/2');

    await tester.tap(find.byTooltip('区分大小写'));
    await tester.pump();
    await waitForText(tester, '1/1');
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
