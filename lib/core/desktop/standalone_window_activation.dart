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
  }) : _visible = !prewarmed {
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
  bool _visible;

  bool get visible => _visible;

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
      if (!_disposed) {
        _setVisible(true);
        await onActivated();
      }
      _activated = true;
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
