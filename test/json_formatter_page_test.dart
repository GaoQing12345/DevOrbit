import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('starts blank without example content', (tester) async {
    final fixture = await JsonFormatterFixture.create();

    await tester.pumpWidget(fixture.widget);

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(fixture.controller.text, isEmpty);
    expect(editor.hint, isNull);
    await disposeEditor(tester);
  });

  testWidgets('shows and toggles nested JSON folding controls', (tester) async {
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
    final indicator = tester.widget<DefaultCodeChunkIndicator>(
      find.byType(DefaultCodeChunkIndicator),
    );
    expect(indicator.controller.value, hasLength(4));

    indicator.controller.collapse(1);
    await tester.pump();

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(editor.controller!.codeLines[1].chunkParent, isTrue);
    expect(fixture.controller.text, nestedJson);
    await tester.pump(const Duration(milliseconds: 350));
    await disposeEditor(tester);
  });

  testWidgets('Control+F opens find for the whole formatter window', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('json-find-input')), findsOneWidget);
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Command+F opens find on macOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('json-find-input')), findsOneWidget);
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Control+H opens replace on Windows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('json-replace-input')), findsOneWidget);
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Command+R opens replace on macOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await JsonFormatterFixture.create();
    await tester.pumpWidget(fixture.widget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('json-replace-input')), findsOneWidget);
    await disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Escape closes find before closing the formatter window', (
    tester,
  ) async {
    var closeCount = 0;
    final fixture = await JsonFormatterFixture.create(
      onEscapeClose: () async => closeCount++,
    );
    await tester.pumpWidget(fixture.widget);
    await tester.tap(find.byTooltip('查找'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const ValueKey('json-find-input')), findsNothing);
    expect(closeCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
    await disposeEditor(tester);
  });

  testWidgets('find panel can replace all matches', (tester) async {
    final fixture = await JsonFormatterFixture.create(text: 'foo foo');
    await tester.pumpWidget(fixture.widget);

    await tester.tap(find.byTooltip('查找'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('json-find-input')),
      'foo',
    );
    await _waitForEnabled(tester, '下一个');
    await tester.tap(find.byTooltip('显示替换'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('json-replace-input')),
      'bar',
    );
    await _waitForEnabled(tester, '全部替换');
    await tester.tap(find.byTooltip('全部替换'));
    await tester.pumpAndSettle();

    expect(fixture.controller.text, 'bar bar');
    await disposeEditor(tester);
  });
}

Future<void> _waitForEnabled(WidgetTester tester, String tooltip) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    final iconButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == tooltip,
    );
    if (tester.widget<IconButton>(iconButton).onPressed != null) return;
  }
  fail('$tooltip 在等待搜索结果后仍不可用');
}
