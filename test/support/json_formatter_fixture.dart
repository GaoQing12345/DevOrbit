import 'package:dev_orbit/core/settings/settings_store.dart';
import 'package:dev_orbit/features/json_formatter/json_document_controller.dart';
import 'package:dev_orbit/features/json_formatter/json_formatter_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JsonFormatterFixture {
  JsonFormatterFixture(this.controller, this.widget);

  final JsonDocumentController controller;
  final Widget widget;

  static Future<JsonFormatterFixture> create({String text = ''}) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final controller = JsonDocumentController();
    if (text.isNotEmpty) controller.userEdit(text);
    final widget = MaterialApp(
      home: Scaffold(
        body: JsonFormatterPage(controller: controller, settings: settings),
      ),
    );
    return JsonFormatterFixture(controller, widget);
  }
}

Future<void> waitForControllerText(
  WidgetTester tester,
  JsonDocumentController controller,
  String expected,
) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (controller.text == expected) return;
  }
  fail('等待 JSON 转换完成超时');
}

Future<void> waitForFoldChunks(WidgetTester tester, int count) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    final indicator = find.byType(DefaultCodeChunkIndicator);
    if (indicator.evaluate().isEmpty) continue;
    if (tester
            .widget<DefaultCodeChunkIndicator>(indicator)
            .controller
            .value
            .length >=
        count) {
      return;
    }
  }
  fail('等待 JSON 折叠区分析超时');
}

Future<void> disposeEditor(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpWidget(const SizedBox.shrink());
}

ClipboardState mockClipboard(WidgetTester tester, {String initialText = ''}) {
  final state = ClipboardState(initialText);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    state.handleMethodCall,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return state;
}

class ClipboardState {
  ClipboardState(this.text);

  String text;

  Future<Object?> handleMethodCall(MethodCall call) async {
    if (call.method == 'Clipboard.getData') return {'text': text};
    if (call.method == 'Clipboard.setData') {
      text = (call.arguments as Map<Object?, Object?>)['text']! as String;
    }
    return null;
  }
}
