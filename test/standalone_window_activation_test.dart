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

    expect(activation.visible, isFalse);
    await activation.initialize();
    expect(activation.visible, isFalse);
    expect(processWindowCalls.map((call) => call.method), [
      'markReadyForActivation',
    ]);
    expect(windowCalls, isEmpty);

    activation.onWindowFocus();
    await Future<void>.delayed(Duration.zero);

    expect(activationCount, 1);
    expect(activation.visible, isTrue);
    expect(windowCalls, isEmpty);
    activation.dispose();
    expect(activation.visible, isFalse);
  });

  test(
    'native activation reveals a prewarmed frame before window focus',
    () async {
      var activationCount = 0;
      final activation = StandaloneWindowActivation(
        prewarmed: true,
        onActivated: () async => activationCount++,
      );
      await activation.initialize();

      expect(activation.visible, isFalse);
      await _sendProcessWindowCall('prepareForActivation');

      expect(activation.visible, isTrue);
      expect(activationCount, 0);
      expect(windowCalls, isEmpty);

      await _sendProcessWindowCall('activationComplete');
      await Future<void>.delayed(Duration.zero);
      expect(activationCount, 1);
      activation.dispose();
    },
  );

  test('cold window is shown and focused before activation work', () async {
    var activationCount = 0;
    final activation = StandaloneWindowActivation(
      prewarmed: false,
      onActivated: () async => activationCount++,
    );

    expect(activation.visible, isTrue);
    await activation.initialize();

    expect(processWindowCalls.map((call) => call.method), [
      'markReadyForActivation',
    ]);
    expect(windowCalls.map((call) => call.method), [
      'isMinimized',
      'show',
      'focus',
    ]);
    expect(activationCount, 1);
    activation.dispose();
  });

  test('reusable window runs activation work again only after close', () async {
    var activationCount = 0;
    final activation = StandaloneWindowActivation(
      prewarmed: true,
      reactivateAfterClose: true,
      onActivated: () async => activationCount++,
    );

    await activation.initialize();
    activation.onWindowFocus();
    await Future<void>.delayed(Duration.zero);
    activation.onWindowFocus();
    await Future<void>.delayed(Duration.zero);
    expect(activationCount, 1);

    activation.onWindowClose();
    expect(activation.visible, isFalse);
    activation.onWindowFocus();
    await Future<void>.delayed(Duration.zero);
    expect(activationCount, 2);
    expect(activation.visible, isTrue);
    activation.dispose();
  });
}

Future<void> _sendProcessWindowCall(String method) async {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('dev_orbit/process_window', message, (_) {});
}
