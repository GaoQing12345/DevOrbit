import 'package:flutter/material.dart';

import '../../core/modules/tool_module.dart';

class OrbitSlot extends StatelessWidget {
  const OrbitSlot({
    super.key,
    required this.index,
    required this.module,
    required this.hovered,
    required this.onHover,
    required this.onExit,
    required this.onPressed,
  });

  final int index;
  final ToolModule? module;
  final bool hovered;
  final VoidCallback onHover;
  final VoidCallback onExit;
  final ValueChanged<ToolModule> onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = module != null;
    final accent = module?.descriptor.accentColor ?? const Color(0xFF6D7A80);
    return MouseRegion(
      onEnter: (_) => onHover(),
      onExit: (_) => onExit(),
      child: Tooltip(
        message: module?.descriptor.title ?? '待添加',
        child: AnimatedScale(
          scale: hovered ? 1.12 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _backgroundColor(enabled, accent),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _borderColor(accent)),
              boxShadow: hovered
                  ? [
                      BoxShadow(
                        color: accent.withAlpha(46),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: IconButton(
              onPressed: enabled ? () => onPressed(module!) : null,
              padding: EdgeInsets.zero,
              color: accent,
              disabledColor: const Color(0xFF7A868B),
              icon: _SlotIcon(index: index, module: module),
            ),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor(bool enabled, Color accent) {
    if (hovered) {
      return Color.alphaBlend(accent.withAlpha(38), const Color(0xE8FFFFFF));
    }
    return enabled ? const Color(0xDEFFFFFF) : const Color(0xA8EEF2F1);
  }

  Color _borderColor(Color accent) {
    return hovered ? accent.withAlpha(210) : const Color(0xA8FFFFFF);
  }
}

class _SlotIcon extends StatelessWidget {
  const _SlotIcon({required this.index, required this.module});

  final int index;
  final ToolModule? module;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(module?.descriptor.icon ?? Icons.add_rounded, size: 25),
        Positioned(
          right: -10,
          bottom: -9,
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5F6B70),
            ),
          ),
        ),
      ],
    );
  }
}

class OrbitToolboxButton extends StatelessWidget {
  const OrbitToolboxButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '打开工具箱',
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xE8FFFFFF),
          border: Border.all(color: const Color(0x9922A98F)),
          boxShadow: const [
            BoxShadow(color: Color(0x300B1B20), blurRadius: 14),
          ],
        ),
        child: IconButton(
          onPressed: onPressed,
          iconSize: 25,
          color: const Color(0xFF168A76),
          icon: const Icon(Icons.grid_view_rounded),
        ),
      ),
    );
  }
}
