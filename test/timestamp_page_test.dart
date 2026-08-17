import 'package:dev_orbit/app/app_theme.dart';
import 'package:dev_orbit/features/timestamp/timestamp_converter.dart';
import 'package:dev_orbit/features/timestamp/timestamp_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

import 'support/json_formatter_fixture.dart';

void main() {
  testWidgets('shows current time and converts in both directions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(920, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 8, 17, 14, 30, 45, 123);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: TimestampPage(now: () => now)),
      ),
    );

    expect(find.text('2026-08-17 14:30:45.123'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('timestamp-input')),
      '1710000000000',
    );
    await tester.pump();
    final timestampDate = DateTime.fromMillisecondsSinceEpoch(1710000000000);
    expect(
      find.text(TimestampConverter.formatDateTime(timestampDate)),
      findsOneWidget,
    );
    expect(find.textContaining('自动识别为毫秒'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('datetime-input')),
      '2026-08-17 14:30:45.123',
    );
    await tester.pump();
    final expected = DateTime(2026, 8, 17, 14, 30, 45, 123);
    expect(find.text(expected.millisecondsSinceEpoch.toString()), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fits the standalone minimum window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(660, 580));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TimestampPage(now: () => DateTime(2026)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('timestamp-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('datetime-input')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('QuickClipboard inserts at the previous timestamp cursor', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    mockClipboard(tester, initialText: 'restored clipboard');
    final nativeClipboard = mockClipboardRevision(tester);
    await tester.pumpWidget(
      MaterialApp(home: TimestampPage(now: () => DateTime(2026))),
    );
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('timestamp-input')),
    );
    field.controller!.value = const TextEditingValue(
      text: '1234',
      selection: TextSelection.collapsed(offset: 2),
    );
    field.focusNode!.requestFocus();
    await tester.pump();

    await _sendWindowEvent('blur');
    field.focusNode!.unfocus();
    await tester.pump();
    nativeClipboard.pendingPasteText = '56';
    await _sendWindowEvent('focus');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(field.controller!.text, '125634');
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
