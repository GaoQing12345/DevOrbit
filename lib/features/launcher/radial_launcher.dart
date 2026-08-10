import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../core/modules/tool_module.dart';
import '../../core/modules/tool_registry.dart';
import 'radial_geometry.dart';

class RadialLauncher extends StatelessWidget {
  const RadialLauncher({
    super.key,
    required this.controller,
    required this.registry,
  });

  final AppController controller;
  final ToolRegistry registry;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _handleKey(event),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        builder: (context, progress, child) {
          return Opacity(
            opacity: progress,
            child: Transform.scale(scale: 0.88 + progress * 0.12, child: child),
          );
        },
        child: _RadialSurface(controller: controller, registry: registry),
      ),
    );
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      controller.dismissRadial();
      return KeyEventResult.handled;
    }
    final index = _numberKeyIndex(event.logicalKey);
    if (index == null) return KeyEventResult.ignored;
    final module = registry.atSlot(index);
    if (module != null) _open(module);
    return KeyEventResult.handled;
  }

  int? _numberKeyIndex(LogicalKeyboardKey key) {
    const keys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
    ];
    final index = keys.indexOf(key);
    return index < 0 ? null : index;
  }

  void _open(ToolModule module) {
    controller.openTool(module.descriptor.id, origin: ToolLaunchOrigin.radial);
  }
}

class _RadialSurface extends StatelessWidget {
  const _RadialSurface({required this.controller, required this.registry});

  final AppController controller;
  final ToolRegistry registry;

  @override
  Widget build(BuildContext context) {
    const geometry = RadialGeometry();
    const slotSize = 54.0;
    const canvasSize = Size.square(332);
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: canvasSize.width,
          height: canvasSize.height,
          decoration: BoxDecoration(
            color: const Color(0xF21A1F24),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF343B43)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              for (var index = 0; index < 8; index++)
                Positioned(
                  left:
                      geometry.positionFor(index, canvasSize).dx - slotSize / 2,
                  top:
                      geometry.positionFor(index, canvasSize).dy - slotSize / 2,
                  child: _RadialSlot(
                    index: index,
                    module: registry.atSlot(index),
                    onPressed: (module) => controller.openTool(
                      module.descriptor.id,
                      origin: ToolLaunchOrigin.radial,
                    ),
                  ),
                ),
              Center(
                child: Tooltip(
                  message: '打开工具箱',
                  child: IconButton.filled(
                    onPressed: controller.showToolbox,
                    iconSize: 28,
                    padding: const EdgeInsets.all(20),
                    icon: const Icon(Icons.apps_rounded),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadialSlot extends StatelessWidget {
  const _RadialSlot({
    required this.index,
    required this.module,
    required this.onPressed,
  });

  final int index;
  final ToolModule? module;
  final ValueChanged<ToolModule> onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = module != null;
    final accent = module?.descriptor.accentColor ?? const Color(0xFF6E7781);
    return Tooltip(
      message: module?.descriptor.title ?? '待添加',
      child: SizedBox.square(
        dimension: 54,
        child: IconButton(
          onPressed: enabled ? () => onPressed(module!) : null,
          style: IconButton.styleFrom(
            backgroundColor: enabled
                ? accent.withAlpha(38)
                : const Color(0xFF242A31),
            foregroundColor: enabled ? accent : const Color(0xFF69727B),
            disabledForegroundColor: const Color(0xFF69727B),
            side: BorderSide(
              color: enabled ? accent.withAlpha(150) : const Color(0xFF3A424B),
            ),
          ),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(module?.descriptor.icon ?? Icons.add_rounded, size: 24),
              Positioned(
                right: -10,
                bottom: -9,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF939CA6)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
