import 'package:dev_orbit/app/app_theme.dart';
import 'package:dev_orbit/features/sql_log/sql_log_controller.dart';
import 'package:dev_orbit/features/sql_log/sql_log_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('converts pasted log and shows formatted output', (tester) async {
    final controller = SqlLogController();
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1040, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SqlLogPage(controller: controller)),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('sql-log-input')),
      '==> Preparing: select * from users where name = ?\n'
      '==> Parameters: Alice(String)',
    );
    await tester.pump(const Duration(milliseconds: 180));

    final output = tester.widget<TextField>(
      find.byKey(const ValueKey('sql-log-output')),
    );
    expect(output.controller!.text, contains("'Alice'"));
    expect(find.text('已识别 1 条 SQL'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fits the standalone minimum window without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const SqlLogPage()),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('sql-log-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('sql-log-output')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('QuickClipboard inserts at the previous log cursor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    mockClipboard(tester, initialText: 'restored clipboard');
    final nativeClipboard = mockClipboardRevision(tester);
    await tester.pumpWidget(const MaterialApp(home: SqlLogPage()));
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('sql-log-input')),
    );
    field.controller!.value = const TextEditingValue(
      text: 'beforeafter',
      selection: TextSelection.collapsed(offset: 6),
    );
    field.focusNode!.requestFocus();
    await tester.pump();

    await _sendWindowEvent('blur');
    field.focusNode!.unfocus();
    await tester.pump();
    nativeClipboard.pendingPasteText = ' inserted ';
    await _sendWindowEvent('focus');
    await tester.pump();

    expect(field.controller!.text, 'before inserted after');
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
