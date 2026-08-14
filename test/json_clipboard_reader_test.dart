import 'package:dev_orbit/core/desktop/desktop_clipboard_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native pending paste avoids a competing system clipboard read',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var systemClipboardReads = 0;
      const nativeChannel = MethodChannel('dev_orbit/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') systemClipboardReads++;
        return {'text': 'restored clipboard'};
      });
      messenger.setMockMethodCallHandler(nativeChannel, (call) async {
        if (call.method == 'takePendingPasteText') return 'QuickClipboard item';
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(nativeChannel, null);
      });

      final text = await const DesktopClipboardReader().readPasteText(
        sessionId: 7,
      );

      expect(text, 'QuickClipboard item');
      expect(systemClipboardReads, 0);
    },
  );

  test('an old discard cannot clear a newer capture session', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    int? activeSession;
    String? pendingText;
    const nativeChannel = MethodChannel('dev_orbit/clipboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      final sessionId =
          (call.arguments as Map<Object?, Object?>)['sessionId']! as int;
      if (call.method == 'armPasteCapture') {
        activeSession = sessionId;
      } else if (call.method == 'discardPendingPasteText') {
        if (activeSession == sessionId) {
          activeSession = null;
          pendingText = null;
        }
      } else if (call.method == 'takePendingPasteText' &&
          activeSession == sessionId) {
        final result = pendingText;
        activeSession = null;
        pendingText = null;
        return result;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));
    const reader = DesktopClipboardReader();

    await reader.armPasteCapture(1);
    await reader.armPasteCapture(2);
    pendingText = 'current session';
    await reader.discardPendingPasteText(1);

    expect(await reader.readCapturedPasteText(2), 'current session');
  });
}
