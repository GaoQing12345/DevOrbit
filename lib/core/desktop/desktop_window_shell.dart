import 'dart:async';
import 'dart:io';

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

  @override
  void dispose() {
    windowManager.removeListener(this);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (DesktopEscapeCloseRegion._takeCurrentEscapeSuppression()) return;
          unawaited(_close());
        },
      },
      child: Focus(focusNode: _focusNode, autofocus: true, child: widget.child),
    );
  }
}

class StandaloneWindowShell extends StatelessWidget {
  const StandaloneWindowShell({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = Platform.isWindows
        ? Column(
            children: [
              WindowsWindowTitleBar(
                title: title,
                onMinimize: () => unawaited(windowManager.minimize()),
                onClose: () => unawaited(windowManager.close()),
              ),
              Expanded(child: child),
            ],
          )
        : child;
    return DesktopEscapeCloseRegion(
      onClose: windowManager.close,
      child: content,
    );
  }
}

class WindowsWindowTitleBar extends StatelessWidget {
  const WindowsWindowTitleBar({
    super.key,
    required this.title,
    required this.onMinimize,
    required this.onClose,
    this.closeTooltip = '关闭',
  });

  final String title;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final String closeTooltip;

  static const height = 40.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: scheme.surfaceContainerLow,
        child: Row(
          children: [
            Expanded(child: _WindowDragArea(title: title)),
            _WindowButton(
              tooltip: '最小化',
              icon: Icons.remove_rounded,
              onPressed: onMinimize,
            ),
            _WindowButton(
              tooltip: closeTooltip,
              icon: Icons.close_rounded,
              onPressed: onClose,
              hoverColor: scheme.errorContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowDragArea extends StatelessWidget {
  const _WindowDragArea({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.hoverColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      hoverColor: hoverColor,
      icon: Icon(icon, size: 18, color: scheme.onSurface),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 46, height: 40),
      style: IconButton.styleFrom(shape: const RoundedRectangleBorder()),
    );
  }
}
