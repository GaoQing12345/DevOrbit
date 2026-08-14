import 'package:dev_orbit/features/json_formatter/json_clipboard_reader.dart';
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

      final text = await const JsonClipboardReader().readPasteText();

      expect(text, 'QuickClipboard item');
      expect(systemClipboardReads, 0);
    },
  );
}
