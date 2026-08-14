import 'package:dev_orbit/core/desktop/standalone_window_activation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowChannel = MethodChannel('window_manager');
  const processWindowChannel = MethodChannel('dev_orbit/process_window');
  final windowCalls = <MethodCall>[];
  final processWindowCalls = <MethodCall>[];

  setUp(() {
    windowCalls.clear();
    processWindowCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          windowCalls.add(call);
          if (call.method == 'isMinimized') return false;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(processWindowChannel, (call) async {
          processWindowCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(processWindowChannel, null);
  });

  test('prewarmed native focus only runs activation work', () async {
    var activationCount = 0;
    final activation = StandaloneWindowActivation(
      prewarmed: true,
      onActivated: () async => activationCount++,
    );

    await activation.initialize();
    expect(processWindowCalls.map((call) => call.method), [
      'markReadyForActivation',
    ]);
    expect(windowCalls, isEmpty);

    activation.onWindowFocus();
    await Future<void>.delayed(Duration.zero);

    expect(activationCount, 1);
    expect(windowCalls, isEmpty);
    activation.dispose();
  });

  test('cold window is shown and focused before activation work', () async {
    var activationCount = 0;
    final activation = StandaloneWindowActivation(
      prewarmed: false,
      onActivated: () async => activationCount++,
    );

    await activation.initialize();

    expect(windowCalls.map((call) => call.method), [
      'isMinimized',
      'show',
      'focus',
    ]);
    expect(activationCount, 1);
    activation.dispose();
  });
}
