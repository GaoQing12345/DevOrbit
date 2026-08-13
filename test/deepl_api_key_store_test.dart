import 'package:dev_orbit/features/translator/deepl_api_key_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev_orbit/credentials-test');
  final calls = <MethodCall>[];
  final store = NativeDeepLApiKeyStore(channel: channel);

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'read') return 'secret';
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reads and writes the DeepL key through the native credential channel',
    () async {
      expect(await store.read(), 'secret');
      await store.write('updated');
      await store.delete();

      expect(calls, [
        isA<MethodCall>()
            .having((call) => call.method, 'method', 'read')
            .having((call) => call.arguments, 'arguments', {
              'key': 'deepl-api-key',
            }),
        isA<MethodCall>()
            .having((call) => call.method, 'method', 'write')
            .having((call) => call.arguments, 'arguments', {
              'key': 'deepl-api-key',
              'value': 'updated',
            }),
        isA<MethodCall>()
            .having((call) => call.method, 'method', 'delete')
            .having((call) => call.arguments, 'arguments', {
              'key': 'deepl-api-key',
            }),
      ]);
    },
  );
}
