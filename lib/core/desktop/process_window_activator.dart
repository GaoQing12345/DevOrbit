import 'package:flutter/services.dart';

abstract interface class ProcessWindowActivator {
  Future<bool> activate(int processId);
}

class NativeProcessWindowActivator implements ProcessWindowActivator {
  NativeProcessWindowActivator({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev_orbit/process_window');

  final MethodChannel _channel;

  @override
  Future<bool> activate(int processId) async {
    return await _channel.invokeMethod<bool>('activate', {
          'processId': processId,
        }) ??
        false;
  }
}
