import 'package:flutter/services.dart';

/// Switches the native window backdrop between the radial launcher and the
/// ordinary tool window.
///
/// AppKit paints the macOS titlebar strip from the window background, so a
/// clear window loses that strip — traffic lights included. Only the radial
/// launcher opts into transparency; every other window keeps the opaque
/// native default.
abstract interface class DesktopWindowEffects {
  Future<void> setRadialMode(bool enabled);
}

class NativeDesktopWindowEffects implements DesktopWindowEffects {
  NativeDesktopWindowEffects({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev_orbit/window_effects');

  final MethodChannel _channel;

  @override
  Future<void> setRadialMode(bool enabled) {
    return _channel.invokeMethod<void>('setRadialMode', {'enabled': enabled});
  }
}
