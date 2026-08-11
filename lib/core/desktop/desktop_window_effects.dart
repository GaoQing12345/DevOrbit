import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class DesktopWindowEffects {
  Future<void> setRadialMode(bool enabled);
}

class NativeDesktopWindowEffects implements DesktopWindowEffects {
  NativeDesktopWindowEffects({MethodChannel? channel, bool? isWindows})
    : _channel = channel ?? const MethodChannel('dev_orbit/window_effects'),
      _isWindows = isWindows ?? Platform.isWindows;

  final MethodChannel _channel;
  final bool _isWindows;

  @override
  Future<void> setRadialMode(bool enabled) async {
    if (!_isWindows) return;
    await _channel.invokeMethod<void>('setRadialMode', {'enabled': enabled});
  }
}
