import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

typedef StandaloneWindowActivated = Future<void> Function();

/// Drives the lifecycle of a standalone tool window.
///
/// Activation is idempotent: the window is shown and focused once, and
/// [onActivated] runs a single time per activation cycle. Tools that can be
/// reopened after closing pass [reactivateAfterClose].
class StandaloneWindowActivation extends ChangeNotifier with WindowListener {
  StandaloneWindowActivation({
    required this.onActivated,
    this.reactivateAfterClose = false,
  }) {
    if (reactivateAfterClose) windowManager.addListener(this);
  }

  final StandaloneWindowActivated onActivated;
  final bool reactivateAfterClose;
  bool _activating = false;
  bool _activated = false;
  bool _disposed = false;
  bool _visible = true;

  bool get visible => _visible;

  Future<void> initialize() async {
    if (_disposed) return;
    await _activateWindow();
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
    if (!reactivateAfterClose) return;
    _setVisible(true);
    unawaited(_activateWindow(alreadyShownAndFocused: true));
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
    if (reactivateAfterClose) windowManager.removeListener(this);
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
