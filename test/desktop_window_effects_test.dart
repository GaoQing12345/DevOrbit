import 'package:dev_orbit/core/desktop/desktop_window_effects.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sends radial mode changes to the Windows native runner', () async {
    const channel = MethodChannel('dev_orbit/window_effects-test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final effects = NativeDesktopWindowEffects(
      channel: channel,
      isWindows: true,
    );

    await effects.setRadialMode(true);
    await effects.setRadialMode(false);

    expect(calls.map((call) => call.method), [
      'setRadialMode',
      'setRadialMode',
    ]);
    expect(calls.map((call) => call.arguments), [
      {'enabled': true},
      {'enabled': false},
    ]);
  });

  test('does not use the native channel outside Windows', () async {
    const channel = MethodChannel('dev_orbit/window_effects-non-windows');
    final effects = NativeDesktopWindowEffects(
      channel: channel,
      isWindows: false,
    );

    await effects.setRadialMode(true);
  });
}
