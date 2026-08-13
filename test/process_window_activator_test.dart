import 'package:dev_orbit/core/desktop/process_window_activator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev_orbit/process-window-test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('activates a window by process ID', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return true;
        });
    final activator = NativeProcessWindowActivator(channel: channel);

    expect(await activator.activate(321), isTrue);
    expect(captured?.method, 'activate');
    expect(captured?.arguments, {'processId': 321});
  });
}
