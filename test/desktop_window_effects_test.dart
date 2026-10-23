import 'package:dev_orbit/core/desktop/desktop_window_effects.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev_orbit/window_effects-test');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('forwards radial mode changes to the native window', () async {
    final effects = NativeDesktopWindowEffects(channel: channel);

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

  test('restores the opaque backdrop when the radial launcher closes', () async {
    final effects = NativeDesktopWindowEffects(channel: channel);

    // A clear window background leaves the native titlebar transparent, so the
    // tool window must explicitly switch the backdrop back.
    await effects.setRadialMode(false);

    expect(calls.single.arguments, {'enabled': false});
  });
}
