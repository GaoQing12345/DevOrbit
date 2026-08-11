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
    final accent = module?.descriptor.accentColor ?? const Color(0xFF77818C);
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
                        color: accent.withAlpha(54),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: IconButton(
              onPressed: enabled ? () => onPressed(module!) : null,
              padding: EdgeInsets.zero,
              color: accent,
              disabledColor: const Color(0xFF69727B),
              icon: _SlotIcon(index: index, module: module),
            ),
          ),
        ),
      ),
    );
  }

  Color _backgroundColor(bool enabled, Color accent) {
    if (hovered) return accent.withAlpha(66);
    return enabled ? const Color(0xF02A3037) : const Color(0xB823292F);
  }

  Color _borderColor(Color accent) {
    return hovered ? accent.withAlpha(230) : const Color(0x4DFFFFFF);
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
              color: Color(0xFF9EA7B0),
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
          color: const Color(0xD91F252B),
          border: Border.all(color: const Color(0x7022C7A9)),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 16),
          ],
        ),
        child: IconButton(
          onPressed: onPressed,
          iconSize: 25,
          color: const Color(0xFFB9F5E9),
          icon: const Icon(Icons.grid_view_rounded),
        ),
      ),
    );
  }
}
