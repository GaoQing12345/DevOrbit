import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'web_text_editor.dart';

class DesktopEscapeCloseRegion extends StatefulWidget {
  const DesktopEscapeCloseRegion({
    super.key,
    required this.onClose,
    required this.child,
  });

  static const doubleEscapeTimeout = Duration(milliseconds: 700);

  final Future<void> Function() onClose;
  final Widget child;

  static int _escapeSuppressionVersion = 0;
  static int? _suppressedEscapeVersion;

  static void consumeCurrentEscape() {
    final version = ++_escapeSuppressionVersion;
    _suppressedEscapeVersion = version;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_suppressedEscapeVersion == version) {
        _suppressedEscapeVersion = null;
      }
    });
  }

  static bool _takeCurrentEscapeSuppression() {
    if (_suppressedEscapeVersion == null) return false;
    _suppressedEscapeVersion = null;
    return true;
  }

  @override
  State<DesktopEscapeCloseRegion> createState() =>
      _DesktopEscapeCloseRegionState();
}

class _DesktopEscapeCloseRegionState extends State<DesktopEscapeCloseRegion>
    with WindowListener {
  final _focusNode = FocusNode(
    debugLabel: 'desktop-window-escape-close-region',
  );
  bool _closing = false;
  bool _awaitingSecondEscape = false;
  Timer? _doubleEscapeTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void onWindowFocus() {
    _restoreWindowFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreWindowFocus();
    });
  }

  @override
  void onWindowBlur() {
    _clearPendingEscape();
  }

  void _restoreWindowFocus() {
    if (!mounted || !_focusNode.canRequestFocus) return;

    // A Flutter TextField in a find/replace overlay has priority over the
    // WebView editor that sits underneath it. Do not let the window shell's
    // Escape focus node (or WebView recovery) steal that input focus.
    final focusedEditable = FocusManager.instance.primaryFocus;
    if (focusedEditable?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null) {
      return;
    }

    // The overlay may have handed Flutter focus to a button or the panel itself
    // while still owning the caret. Window activation is not an editor
    // interaction, so the caret stays in the overlay either way.
    if (DesktopWebTextEditor.flutterFieldOwnsEditing) return;

    // A WebView editor has a native responder/focus target in addition to the
    // Flutter focus tree. Restoring this shell's Escape node here would steal
    // the keyboard immediately after a clipboard picker returns, leaving the
    // browser caret visible but unable to receive input.
    if (DesktopWebTextEditor.hasActiveEditor) {
      DesktopWebTextEditor.restoreActiveEditorFocus();
      return;
    }

    // A dialog, popup menu, or dropdown route must keep ownership of Escape.
    // This also covers the brief moment where that route has not restored its
    // primary focus yet after the native window becomes active.
    final regionRoute = ModalRoute.of(context);
    if (regionRoute != null && !regionRoute.isCurrent) return;

    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null ||
        identical(primaryFocus, FocusManager.instance.rootScope)) {
      _focusNode.requestFocus();
      return;
    }

    final focusInsideRegion =
        identical(primaryFocus, _focusNode) ||
        primaryFocus.ancestors.contains(_focusNode);
    if (focusInsideRegion) return;

    // A focus scope outside the home route belongs to an overlay route. Do not
    // steal it when the app is reactivated.
    final primaryContext = primaryFocus.context;
    if (primaryContext != null &&
        ModalRoute.of(primaryContext) != regionRoute) {
      return;
    }
    _focusNode.requestFocus();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      await widget.onClose();
    } finally {
      _closing = false;
    }
  }

  void _handleEscape() {
    if (DesktopEscapeCloseRegion._takeCurrentEscapeSuppression()) {
      _clearPendingEscape();
      return;
    }

    if (_awaitingSecondEscape) {
      _clearPendingEscape();
      unawaited(_close());
      return;
    }

    _awaitingSecondEscape = true;
    _doubleEscapeTimer = Timer(
      DesktopEscapeCloseRegion.doubleEscapeTimeout,
      _clearPendingEscape,
    );
  }

  void _clearPendingEscape() {
    _doubleEscapeTimer?.cancel();
    _doubleEscapeTimer = null;
    _awaitingSecondEscape = false;
  }

  @override
  void dispose() {
    _clearPendingEscape();
    windowManager.removeListener(this);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _handleEscape();
        },
      },
      child: Focus(focusNode: _focusNode, autofocus: true, child: widget.child),
    );
  }
}

class StandaloneWindowShell extends StatelessWidget {
  const StandaloneWindowShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DesktopEscapeCloseRegion(onClose: windowManager.close, child: child);
  }
}
