import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

typedef StandaloneWindowActivated = Future<void> Function();

class StandaloneWindowActivation extends ChangeNotifier with WindowListener {
  StandaloneWindowActivation({
    required this.prewarmed,
    required this.onActivated,
    this.reactivateAfterClose = false,
    this.renderWhilePrewarmed = false,
  }) : _visible = !prewarmed || renderWhilePrewarmed {
    _processWindowChannel.setMethodCallHandler(_handleNativeCall);
    if (_listensToWindow) windowManager.addListener(this);
  }

  static const _processWindowChannel = MethodChannel(
    'dev_orbit/process_window',
  );

  final bool prewarmed;
  final StandaloneWindowActivated onActivated;
  final bool reactivateAfterClose;
  final bool renderWhilePrewarmed;
  bool _activating = false;
  bool _activated = false;
  bool _disposed = false;
  bool _visible;

  bool get visible => _visible;

  bool get _listensToWindow => prewarmed || reactivateAfterClose;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed) return;
    if (call.method == 'activationComplete') {
      unawaited(_activateWindow(alreadyShownAndFocused: true));
      return;
    }
    if (call.method != 'prepareForActivation') return;

    // Windows keeps prewarmed helper HWNDs hidden on an empty Flutter frame.
    // Rebuild the actual page first; the native runner shows the window from
    // that frame's completion callback, avoiding a transparent first paint.
    if (_visible) {
      // A heavyweight platform view may already have been rendered behind a
      // hidden native HWND. Still schedule a frame so the runner's activation
      // callback has a deterministic point at which to reveal the window.
      notifyListeners();
    } else {
      _setVisible(true);
    }
  }

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
      if (!_disposed) {
        _setVisible(true);
        await onActivated();
        _activated = true;
      }
    } finally {
      _activating = false;
    }
  }

  @override
  void onWindowFocus() {
    if (_listensToWindow) {
      _setVisible(true);
      unawaited(_activateWindow(alreadyShownAndFocused: true));
    }
  }

  @override
  void onWindowClose() {
    if (reactivateAfterClose) _activated = false;
    _setVisible(false);
  }

  @override
  void dispose() {
    _visible = false;
    _disposed = true;
    _processWindowChannel.setMethodCallHandler(null);
    if (_listensToWindow) windowManager.removeListener(this);
    super.dispose();
  }

  void _setVisible(bool value) {
    if (_visible == value || _disposed) return;
    _visible = value;
    notifyListeners();
  }
}

class StandaloneWindowVisibility extends StatelessWidget {
  const StandaloneWindowVisibility({
    super.key,
    required this.activation,
    required this.child,
  });

  final StandaloneWindowActivation activation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: activation,
      builder: (context, child) => Visibility(
        visible: activation.visible,
        maintainState: true,
        child: child!,
      ),
      child: child,
    );
  }
}
