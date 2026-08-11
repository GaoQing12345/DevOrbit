import 'package:dev_orbit/core/desktop/desktop_cursor_locator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the native cursor coordinate channel on macOS', () async {
    const channel = MethodChannel('dev_orbit/cursor-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getCursorScreenPoint');
          return {'dx': 420.5, 'dy': 315.25};
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final locator = NativeDesktopCursorLocator(
      channel: channel,
      isMacOS: true,
      fallback: () async => const Offset(-1, -1),
    );

    expect(await locator.getPosition(), const Offset(420.5, 315.25));
  });

  test('uses screen retriever coordinates outside macOS', () async {
    const expected = Offset(640, 480);
    final locator = NativeDesktopCursorLocator(
      isMacOS: false,
      fallback: () async => expected,
    );

    expect(await locator.getPosition(), expected);
  });
}
