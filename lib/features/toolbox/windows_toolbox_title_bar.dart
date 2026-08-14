import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/desktop/desktop_window_shell.dart';

class WindowsToolboxTitleBar extends StatelessWidget {
  const WindowsToolboxTitleBar({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return WindowsWindowTitleBar(
      title: 'DevOrbit',
      onMinimize: controller.minimize,
      onClose: controller.hide,
      closeTooltip: '关闭到后台',
    );
  }
}
