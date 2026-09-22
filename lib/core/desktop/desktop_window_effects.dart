import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Window background for a tool window that shows its native titlebar.
///
/// AppKit paints the macOS titlebar strip from the window background, so a
/// clear window loses the titlebar — traffic lights included — against the
/// desktop. macOS therefore keeps the opaque native default, while the Windows
/// runner draws its own titlebar and needs the window clear.
///
/// Returns `null` when the platform default must be left untouched.
Color? desktopToolWindowBackground({bool? isWindows}) =>
    (isWindows ?? Platform.isWindows) ? Colors.transparent : null;

abstract interface class DesktopWindowEffects {
  /// Switches the native window between the radial launcher backdrop and the
  /// ordinary tool-window backdrop.
  ///
  /// macOS uses it to keep the window background opaque while a native titlebar
  /// is shown: AppKit paints that strip from the window background, so a clear
  /// window loses its titlebar.
  Future<void> setRadialMode(bool enabled);
}

class NativeDesktopWindowEffects implements DesktopWindowEffects {
  NativeDesktopWindowEffects({
    MethodChannel? channel,
    bool? isWindows,
    bool? isMacOS,
  }) : _channel = channel ?? const MethodChannel('dev_orbit/window_effects'),
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS;

  final MethodChannel _channel;
  final bool _isWindows;
  final bool _isMacOS;

  @override
  Future<void> setRadialMode(bool enabled) async {
    if (!_isWindows && !_isMacOS) return;
    await _channel.invokeMethod<void>('setRadialMode', {'enabled': enabled});
  }
}
