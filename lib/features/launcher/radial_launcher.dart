import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../core/modules/tool_module.dart';
import '../../core/modules/tool_registry.dart';
import 'orbit_ring_controls.dart';
import 'orbit_ring_painter.dart';
import 'radial_geometry.dart';

class RadialLauncher extends StatefulWidget {
  const RadialLauncher({
    super.key,
    required this.controller,
    required this.registry,
  });

  final AppController controller;
  final ToolRegistry registry;

  @override
  State<RadialLauncher> createState() => _RadialLauncherState();
}

class _RadialLauncherState extends State<RadialLauncher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final Animation<double> _entryAnimation;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
    _entryAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _handleKey(event),
      child: AnimatedBuilder(
        animation: _entryAnimation,
        builder: (context, child) {
          final progress = disableAnimations ? 1.0 : _entryAnimation.value;
          return Opacity(
            opacity: progress,
            child: Transform.rotate(
              angle: (1 - progress) * -0.035,
              child: Transform.scale(scale: 0.9 + progress * 0.1, child: child),
            ),
          );
        },
        child: _OrbitSurface(
          controller: widget.controller,
          registry: widget.registry,
          hoveredIndex: _hoveredIndex,
          onHover: _updateHoveredIndex,
        ),
      ),
    );
  }

  void _updateHoveredIndex(int? index) {
    if (!mounted || _hoveredIndex == index) return;
    setState(() => _hoveredIndex = index);
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.dismissRadial();
      return KeyEventResult.handled;
    }
    final index = _numberKeyIndex(event.logicalKey);
    if (index == null) return KeyEventResult.ignored;
    final module = widget.registry.atSlot(index);
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
    widget.controller.openTool(
      module.descriptor.id,
      origin: ToolLaunchOrigin.radial,
    );
  }
}

class _OrbitSurface extends StatelessWidget {
  const _OrbitSurface({
    required this.controller,
    required this.registry,
    required this.hoveredIndex,
    required this.onHover,
  });

  static const _canvasSize = Size.square(332);
  static const _slotSize = 56.0;

  final AppController controller;
  final ToolRegistry registry;
  final int? hoveredIndex;
  final ValueChanged<int?> onHover;

  @override
  Widget build(BuildContext context) {
    const geometry = RadialGeometry();
    final hoveredModule = hoveredIndex == null
        ? null
        : registry.atSlot(hoveredIndex!);
    final hoveredColor =
        hoveredModule?.descriptor.accentColor ?? const Color(0xFF22C7A9);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: MouseRegion(
          onExit: (_) => onHover(null),
          child: SizedBox.fromSize(
            size: _canvasSize,
            child: Stack(
              children: [
                CustomPaint(
                  key: const ValueKey('orbit-ring-track'),
                  size: _canvasSize,
                  painter: OrbitRingPainter(
                    hoveredIndex: hoveredIndex,
                    hoveredColor: hoveredColor,
                  ),
                ),
                for (var index = 0; index < 8; index++)
                  Positioned(
                    left:
                        geometry.positionFor(index, _canvasSize).dx -
                        _slotSize / 2,
                    top:
                        geometry.positionFor(index, _canvasSize).dy -
                        _slotSize / 2,
                    child: OrbitSlot(
                      index: index,
                      module: registry.atSlot(index),
                      hovered: hoveredIndex == index,
                      onHover: () => onHover(index),
                      onExit: () => onHover(null),
                      onPressed: (module) => controller.openTool(
                        module.descriptor.id,
                        origin: ToolLaunchOrigin.radial,
                      ),
                    ),
                  ),
                Center(
                  child: OrbitToolboxButton(onPressed: controller.showToolbox),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
