import 'package:dev_orbit/app/app_theme.dart';
import 'package:dev_orbit/core/desktop/desktop_window_shell.dart';
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

  static Future<JsonFormatterFixture> create({
    String text = '',
    Widget? sibling,
    bool showSibling = false,
    Future<void> Function()? onEscapeClose,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final controller = JsonDocumentController();
    if (text.isNotEmpty) controller.userEdit(text);
    final page = JsonFormatterPage(controller: controller, settings: settings);
    Widget body = sibling == null
        ? page
        : IndexedStack(index: showSibling ? 1 : 0, children: [page, sibling]);
    if (onEscapeClose != null) {
      body = DesktopEscapeCloseRegion(onClose: onEscapeClose, child: body);
    }
    final widget = MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(body: body),
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
  const nativeChannel = MethodChannel('dev_orbit/clipboard');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    state.handleMethodCall,
  );
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    nativeChannel,
    (_) async => null,
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      nativeChannel,
      null,
    );
  });
  return state;
}

ClipboardRevisionState mockClipboardRevision(
  WidgetTester tester, {
  int initialRevision = 1,
}) {
  const channel = MethodChannel('dev_orbit/clipboard');
  final state = ClipboardRevisionState(initialRevision);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    state.handleMethodCall,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
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

class ClipboardRevisionState {
  ClipboardRevisionState(this.revision);

  int revision;
  String? pendingPasteText;
  int? armedSessionId;
  bool observedChange = false;
  bool pasteCapturePrearmed = true;

  Future<Object?> handleMethodCall(MethodCall call) async {
    if (call.method == 'getChangeCount') return revision;
    if (call.method == 'supportsPasteCapture') return true;
    if (call.method == 'armPasteCapture') {
      armedSessionId = _sessionId(call);
      pendingPasteText = null;
      observedChange = false;
      return pasteCapturePrearmed;
    }
    if (call.method == 'discardPendingPasteText') {
      if (_sessionId(call) == armedSessionId) {
        pendingPasteText = null;
        armedSessionId = null;
        observedChange = false;
      }
      return null;
    }
    if (call.method == 'didPasteCaptureObserveChange') {
      return _sessionId(call) == armedSessionId &&
          (observedChange || pendingPasteText != null);
    }
    if (call.method == 'takePendingPasteText') {
      if (_sessionId(call) != armedSessionId) return null;
      final text = pendingPasteText;
      if (text != null) {
        pendingPasteText = null;
        armedSessionId = null;
        observedChange = false;
      }
      return text;
    }
    return null;
  }

  int? _sessionId(MethodCall call) {
    return (call.arguments as Map<Object?, Object?>?)?['sessionId'] as int?;
  }
}
