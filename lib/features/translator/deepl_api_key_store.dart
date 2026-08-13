import 'package:flutter/services.dart';

abstract interface class DeepLApiKeyStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

class NativeDeepLApiKeyStore implements DeepLApiKeyStore {
  const NativeDeepLApiKeyStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev_orbit/credentials');

  static const _key = 'deepl-api-key';
  final MethodChannel _channel;

  @override
  Future<String?> read() =>
      _channel.invokeMethod<String>('read', {'key': _key});

  @override
  Future<void> write(String value) {
    return _channel.invokeMethod<void>('write', {'key': _key, 'value': value});
  }

  @override
  Future<void> delete() => _channel.invokeMethod<void>('delete', {'key': _key});
}
