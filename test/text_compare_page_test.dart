import 'package:dev_orbit/features/text_compare/text_compare_controller.dart';
import 'package:dev_orbit/features/text_compare/text_compare_engine.dart';
import 'package:dev_orbit/features/text_compare/text_compare_models.dart';
import 'package:dev_orbit/features/text_compare/text_compare_page.dart';
import 'package:dev_orbit/features/text_compare/text_compare_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('shows two editable panes and compare controls', (tester) async {
    final controller = TextCompareController(service: _ImmediateService());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            height: 720,
            child: TextComparePage(controller: controller),
          ),
        ),
      ),
    );

    expect(find.text('旧文本'), findsOneWidget);
    expect(find.text('新文本'), findsOneWidget);
    expect(find.text('开始比对'), findsOneWidget);
    expect(find.text('忽略大小写'), findsOneWidget);
    expect(find.text('忽略行尾空白'), findsOneWidget);
    expect(find.byType(CodeEditor), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows diff status without overflowing the minimum window', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 560);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = TextCompareController(service: _ImmediateService());
    addTearDown(controller.dispose);
    controller.updateLeft('alpha\nold value');
    controller.updateRight('alpha\nnew value\nadded');
    await controller.compare();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextComparePage(controller: controller)),
      ),
    );

    expect(find.text('新增 1 行 · 删除 0 行 · 修改 1 行'), findsOneWidget);
    expect(find.byType(CodeEditor), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('iCopy inserts into the previous text comparison cursor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = TextCompareController(service: _ImmediateService());
    addTearDown(controller.dispose);
    controller.updateLeft('abcdef');
    mockClipboard(tester, initialText: 'restored clipboard');
    final nativeClipboard = mockClipboardRevision(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextComparePage(controller: controller)),
      ),
    );
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor).first);
    editor.controller!.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );
    editor.focusNode!.requestFocus();
    await tester.pump();

    await _sendWindowEvent('blur');
    editor.focusNode!.unfocus();
    await tester.pump();
    nativeClipboard.pendingPasteText = 'iCopy';
    await _sendWindowEvent('focus');
    await tester.pump();

    expect(editor.controller!.text, 'abciCopydef');
    expect(controller.leftText, 'abciCopydef');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _sendWindowEvent(String eventName) async {
  windowManager.hasListeners;
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('onEvent', {'eventName': eventName}),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('window_manager', message, (_) {});
}

class _ImmediateService implements TextCompareService {
  @override
  Future<TextDiffResult> compare({
    required String left,
    required String right,
    required TextCompareOptions options,
  }) async {
    return const TextCompareEngine().compare(
      left: left,
      right: right,
      options: options,
    );
  }
}
