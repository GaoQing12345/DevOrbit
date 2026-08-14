import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class DesktopEscapeCloseRegion extends StatefulWidget {
  const DesktopEscapeCloseRegion({
    super.key,
    required this.onClose,
    required this.child,
  });

  final Future<void> Function() onClose;
  final Widget child;

  @override
  State<DesktopEscapeCloseRegion> createState() =>
      _DesktopEscapeCloseRegionState();
}

class _DesktopEscapeCloseRegionState extends State<DesktopEscapeCloseRegion> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    unawaited(widget.onClose());
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
