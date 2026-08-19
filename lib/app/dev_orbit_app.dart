import 'package:flutter/material.dart';

import '../core/desktop/desktop_window_shell.dart';
import '../core/modules/tool_registry.dart';
import '../core/settings/settings_store.dart';
import '../features/launcher/radial_launcher.dart';
import '../features/toolbox/toolbox_shell.dart';
import 'app_controller.dart';
import 'app_theme.dart';

class DevOrbitApp extends StatefulWidget {
  const DevOrbitApp({
    super.key,
    required this.controller,
    required this.registry,
    required this.settings,
    required this.startHidden,
  });

  final AppController controller;
  final ToolRegistry registry;
  final SettingsStore settings;
  final bool startHidden;

  @override
  State<DevOrbitApp> createState() => _DevOrbitAppState();
}

class _DevOrbitAppState extends State<DevOrbitApp> {
  late final Listenable _appListenable;

  @override
  void initState() {
    super.initState();
    _appListenable = Listenable.merge([widget.controller, widget.settings]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.afterFirstFrame(startHidden: widget.startHidden);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appListenable,
      builder: (context, child) {
        return MaterialApp(
          title: 'DevOrbit',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: widget.settings.value.themeMode,
          home: DesktopEscapeCloseRegion(
            onClose: widget.controller.hide,
            child: _AppViewport(
              controller: widget.controller,
              registry: widget.registry,
              settings: widget.settings,
            ),
          ),
        );
      },
    );
  }
}

class _AppViewport extends StatelessWidget {
  const _AppViewport({
    required this.controller,
    required this.registry,
    required this.settings,
  });

  final AppController controller;
  final ToolRegistry registry;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    final showRadial = controller.mode == AppViewMode.radial;
    final showToolbox =
        controller.mode == AppViewMode.toolbox ||
        controller.mode == AppViewMode.tool;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Visibility(
            visible: showToolbox,
            maintainState: true,
            child: ToolboxShell(
              controller: controller,
              registry: registry,
              settings: settings,
            ),
          ),
          if (showRadial)
            RadialLauncher(controller: controller, registry: registry),
        ],
      ),
    );
  }
}
