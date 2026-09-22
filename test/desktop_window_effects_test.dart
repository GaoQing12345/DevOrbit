import 'package:dev_orbit/core/desktop/desktop_window_effects.dart';
import 'package:flutter/material.dart';
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
      isMacOS: false,
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

  test('sends radial mode changes to the macOS native runner', () async {
    const channel = MethodChannel('dev_orbit/window_effects-macos');
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
      isWindows: false,
      isMacOS: true,
    );

    // macOS restores the opaque window backdrop that keeps the native titlebar
    // visible once the radial launcher is done.
    await effects.setRadialMode(false);
    await effects.setRadialMode(true);

    expect(calls.map((call) => call.arguments), [
      {'enabled': false},
      {'enabled': true},
    ]);
  });

  test('does not use the native channel outside Windows and macOS', () async {
    const channel = MethodChannel('dev_orbit/window_effects-non-windows');
    final effects = NativeDesktopWindowEffects(
      channel: channel,
      isWindows: false,
      isMacOS: false,
    );

    await effects.setRadialMode(true);
  });

  test('macOS tool windows keep an opaque window background', () {
    // A clear window background leaves the native titlebar transparent, which
    // is exactly the regression reported after a macOS update.
    expect(desktopToolWindowBackground(isWindows: false), isNull);
    expect(desktopToolWindowBackground(isWindows: true), Colors.transparent);
  });
}
