import 'package:dev_orbit/core/desktop/desktop_cursor_locator.dart';
import 'package:dev_orbit/core/desktop/desktop_shell.dart';
import 'package:dev_orbit/core/desktop/desktop_window_effects.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowChannel = MethodChannel('window_manager');
  const screenChannel = MethodChannel(
    'dev.leanflutter.plugins/screen_retriever',
  );
  late List<String> events;

  setUp(() {
    events = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          events.add(_describeWindowCall(call));
          return switch (call.method) {
            'isVisible' || 'isMinimized' => false,
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(screenChannel, (call) async {
          if (call.method == 'getAllDisplays') {
            return {
              'displays': [
                {
                  'id': 'primary',
                  'size': {'width': 1920.0, 'height': 1080.0},
                  'visiblePosition': {'dx': 0.0, 'dy': 0.0},
                  'visibleSize': {'width': 1920.0, 'height': 1040.0},
                  'scaleFactor': 1.0,
                },
              ],
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(screenChannel, null);
  });

  test(
    'initial hidden startup does not perform a radial style reset',
    () async {
      final shell = NativeDesktopShell(
        windowEffects: _RecordingWindowEffects(events),
        cursorLocator: const _FixedCursorLocator(),
      );

      await shell.hideRadial();

      expect(events, ['hide']);
    },
  );

  for (final platform in [
    (name: 'Windows', isWindows: true),
    (name: 'macOS', isWindows: false),
  ]) {
    test(
      '${platform.name} restores normal window state after radial hides',
      () async {
        final shell = NativeDesktopShell(
          windowEffects: _RecordingWindowEffects(events),
          cursorLocator: const _FixedCursorLocator(),
          isWindows: platform.isWindows,
          isMacOS: !platform.isWindows,
        );
        await shell.showRadial();
        events.clear();

        await shell.hideRadial();

        expect(events, [
          'hide',
          'setMaximumSize:10000.0x10000.0',
          'setMinimumSize:760.0x520.0',
          'setResizable:true',
          'setAlwaysOnTop:false',
          'setSkipTaskbar:false',
          platform.isWindows
              ? 'setTitleBarStyle:hidden:false'
              : 'setTitleBarStyle:normal:true',
          'radialMode:false',
          'setHasShadow:true',
        ]);
      },
    );
  }
}

String _describeWindowCall(MethodCall call) {
  final arguments = call.arguments;
  if (arguments is! Map) return call.method;
  return switch (call.method) {
    'setMaximumSize' || 'setMinimumSize' =>
      '${call.method}:${arguments['width']}x${arguments['height']}',
    'setResizable' => '${call.method}:${arguments['isResizable']}',
    'setAlwaysOnTop' => '${call.method}:${arguments['isAlwaysOnTop']}',
    'setSkipTaskbar' => '${call.method}:${arguments['isSkipTaskbar']}',
    'setTitleBarStyle' =>
      '${call.method}:${arguments['titleBarStyle']}:'
          '${arguments['windowButtonVisibility']}',
    'setHasShadow' => '${call.method}:${arguments['hasShadow']}',
    _ => call.method,
  };
}

class _RecordingWindowEffects implements DesktopWindowEffects {
  _RecordingWindowEffects(this.events);

  final List<String> events;

  @override
  Future<void> setRadialMode(bool enabled) async {
    events.add('radialMode:$enabled');
  }
}

class _FixedCursorLocator implements DesktopCursorLocator {
  const _FixedCursorLocator();

  @override
  Future<Offset> getPosition() async => const Offset(960, 520);
}
