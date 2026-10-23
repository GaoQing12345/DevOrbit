import 'package:dev_orbit/core/desktop/desktop_window_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets('two consecutive Escapes close the active desktop window', (
    tester,
  ) async {
    var closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopEscapeCloseRegion(
          onClose: () async => closeCount++,
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('two consecutive Escapes close without an editable focus', (
    tester,
  ) async {
    var closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopEscapeCloseRegion(
          onClose: () async => closeCount++,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('Escape presses separated by the timeout do not close a window', (
    tester,
  ) async {
    var closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopEscapeCloseRegion(
          onClose: () async => closeCount++,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(DesktopEscapeCloseRegion.doubleEscapeTimeout);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('Escape focus is restored when the window is activated again', (
    tester,
  ) async {
    var closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopEscapeCloseRegion(
          onClose: () async => closeCount++,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _sendWindowEvent('blur');
    await _sendWindowEvent('focus');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
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
