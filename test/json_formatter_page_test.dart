import 'package:dev_orbit/core/settings/settings_store.dart';
import 'package:dev_orbit/features/json_formatter/json_document_controller.dart';
import 'package:dev_orbit/features/json_formatter/json_formatter_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('starts blank without example content', (tester) async {
    final fixture = await _PageFixture.create();

    await tester.pumpWidget(fixture.widget);

    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    expect(fixture.controller.text, isEmpty);
    expect(editor.hint, isNull);
    await _disposeEditor(tester);
  });

  testWidgets('Control+F opens find for the whole formatter window', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await _PageFixture.create();
    await tester.pumpWidget(fixture.widget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('json-find-input')), findsOneWidget);
    await _disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Command+F opens find on macOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final fixture = await _PageFixture.create();
    await tester.pumpWidget(fixture.widget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('json-find-input')), findsOneWidget);
    await _disposeEditor(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('find panel can replace all matches', (tester) async {
    final fixture = await _PageFixture.create(text: 'foo foo');
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
    await _disposeEditor(tester);
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

Future<void> _disposeEditor(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpWidget(const SizedBox.shrink());
}

class _PageFixture {
  _PageFixture(this.controller, this.widget);

  final JsonDocumentController controller;
  final Widget widget;

  static Future<_PageFixture> create({String text = ''}) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final controller = JsonDocumentController();
    if (text.isNotEmpty) controller.userEdit(text);
    final widget = MaterialApp(
      home: Scaffold(
        body: JsonFormatterPage(controller: controller, settings: settings),
      ),
    );
    return _PageFixture(controller, widget);
  }
}
