import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/modules/tool_module.dart';
import '../../core/modules/tool_registry.dart';
import '../../core/widgets/mac_ui.dart';

class ToolboxHome extends StatelessWidget {
  const ToolboxHome({
    super.key,
    required this.controller,
    required this.registry,
  });

  final AppController controller;
  final ToolRegistry registry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MacPageScaffold(
      title: '工具箱',
      subtitle: '已安装 ${registry.modules.length} 个工具，随时处理日常开发任务',
      children: [
        MacGroup(
          title: '全部工具',
          children: [
            for (final module in registry.modules)
              _ToolRow(
                module: module,
                onPressed: () => controller.openTool(module.descriptor.id),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(
              Icons.keyboard_command_key_rounded,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '按下全局快捷键可随时唤出八槽轮盘',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            OrbitMark(size: 14),
          ],
        ),
      ],
    );
  }
}

class _ToolRow extends StatefulWidget {
  const _ToolRow({required this.module, required this.onPressed});

  final ToolModule module;
  final VoidCallback onPressed;

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final descriptor = widget.module.descriptor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 52,
          color: _hovered ? scheme.surfaceContainerLow : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: descriptor.accentColor.withAlpha(
                    theme.brightness == Brightness.dark ? 46 : 28,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  descriptor.icon,
                  size: 15,
                  color: descriptor.accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      descriptor.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      descriptor.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: scheme.onSurfaceVariant.withAlpha(_hovered ? 200 : 110),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
