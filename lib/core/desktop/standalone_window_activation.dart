import 'dart:async';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

typedef StandaloneWindowActivated = Future<void> Function();

class StandaloneWindowActivation with WindowListener {
  StandaloneWindowActivation({
    required this.prewarmed,
    required this.onActivated,
    this.reactivateAfterClose = false,
  }) {
    if (_listensToWindow) windowManager.addListener(this);
  }

  static const _processWindowChannel = MethodChannel(
    'dev_orbit/process_window',
  );

  final bool prewarmed;
  final StandaloneWindowActivated onActivated;
  final bool reactivateAfterClose;
  bool _activating = false;
  bool _activated = false;
  bool _disposed = false;

  bool get _listensToWindow => prewarmed || reactivateAfterClose;

  Future<void> initialize() async {
    if (_disposed) return;
    await _markReadyForActivation();
    if (prewarmed) return;
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
    if (_listensToWindow) {
      unawaited(_activateWindow(alreadyShownAndFocused: true));
    }
  }

  @override
  void onWindowClose() {
    if (reactivateAfterClose) _activated = false;
  }

  void dispose() {
    _disposed = true;
    if (_listensToWindow) windowManager.removeListener(this);
  }
}
