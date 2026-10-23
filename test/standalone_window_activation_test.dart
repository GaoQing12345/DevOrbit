import 'package:dev_orbit/core/desktop/standalone_window_activation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowChannel = MethodChannel('window_manager');
  final windowCalls = <MethodCall>[];

  setUp(() {
    windowCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
          windowCalls.add(call);
          if (call.method == 'isMinimized') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
  });

  test('window is shown and focused before activation work', () async {
    var activationCount = 0;
    final activation = StandaloneWindowActivation(
      onActivated: () async => activationCount++,
    );

    expect(activation.visible, isTrue);
    await activation.initialize();

    expect(windowCalls.map((call) => call.method), [
      'isMinimized',
      'show',
      'focus',
    ]);
    expect(activationCount, 1);
    activation.dispose();
  });

  test('activation work runs once per activation cycle', () async {
    var activationCount = 0;
    final activation = StandaloneWindowActivation(
      onActivated: () async => activationCount++,
    );

    await activation.initialize();
    await activation.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(activationCount, 1);
    activation.dispose();
  });

  test('reusable window runs activation work again only after close', () async {
    var activationCount = 0;
    final activation = StandaloneWindowActivation(
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

  test('a single-use window ignores window focus events', () async {
    var activationCount = 0;
    final activation = StandaloneWindowActivation(
      onActivated: () async => activationCount++,
    );

    await activation.initialize();
    activation.onWindowClose();
    activation.onWindowFocus();
    await Future<void>.delayed(Duration.zero);

    expect(activationCount, 1);
    expect(activation.visible, isFalse);
    activation.dispose();
  });
}
