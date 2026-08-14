import 'dart:async';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

typedef StandaloneWindowActivated = Future<void> Function();

class StandaloneWindowActivation with WindowListener {
  StandaloneWindowActivation({
    required this.prewarmed,
    required this.onActivated,
  }) {
    if (prewarmed) windowManager.addListener(this);
  }

  static const _processWindowChannel = MethodChannel(
    'dev_orbit/process_window',
  );

  final bool prewarmed;
  final StandaloneWindowActivated onActivated;
  bool _activating = false;
  bool _activated = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_disposed) return;
    if (prewarmed) {
      await _markReadyForActivation();
      return;
    }
    await _activateWindow();
  }

  Future<void> _markReadyForActivation() async {
    try {
      await _processWindowChannel.invokeMethod<void>('markReadyForActivation');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> _activateWindow({bool alreadyShownAndFocused = false}) async {
    if (_activating || _activated || _disposed) return;
    _activating = true;
    try {
      if (!alreadyShownAndFocused) {
        await windowManager.show();
        await windowManager.focus();
      }
      if (!_disposed) await onActivated();
      _activated = true;
    } finally {
      _activating = false;
    }
  }

  @override
  void onWindowFocus() {
    if (prewarmed) {
      unawaited(_activateWindow(alreadyShownAndFocused: true));
    }
  }

  void dispose() {
    _disposed = true;
    if (prewarmed) windowManager.removeListener(this);
  }
}
