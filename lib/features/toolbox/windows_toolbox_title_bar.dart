import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_controller.dart';

class WindowsToolboxTitleBar extends StatelessWidget {
  const WindowsToolboxTitleBar({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ColoredBox(
        color: scheme.surfaceContainerLow,
        child: Row(
          children: [
            const Expanded(child: _WindowDragArea()),
            _WindowButton(
              tooltip: '最小化',
              icon: Icons.remove_rounded,
              onPressed: controller.minimize,
            ),
            _WindowButton(
              tooltip: '关闭到后台',
              icon: Icons.close_rounded,
              onPressed: controller.hide,
              hoverColor: scheme.errorContainer,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowDragArea extends StatelessWidget {
  const _WindowDragArea();

  @override
  Widget build(BuildContext context) {
    return const DragToMoveArea(
      child: Padding(
        padding: EdgeInsets.only(left: 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'DevOrbit',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      hoverColor: hoverColor,
      icon: Icon(icon, size: 18),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 46, height: 40),
      style: IconButton.styleFrom(shape: const RoundedRectangleBorder()),
    );
  }
}
