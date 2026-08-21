import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/modules/tool_module.dart';
import '../../core/modules/tool_registry.dart';

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
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(36, 32, 36, 40),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withAlpha(150),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.primary.withAlpha(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest.withAlpha(220),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: scheme.primary,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('工具箱', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 5),
                      Text(
                        '已安装 ${registry.modules.length} 个工具，随时处理日常开发任务',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        for (final module in registry.modules)
          _ToolRow(
            module: module,
            onPressed: () => controller.openTool(module.descriptor.id),
          ),
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.module, required this.onPressed});

  final ToolModule module;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final descriptor = module.descriptor;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: descriptor.accentColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(descriptor.icon, color: descriptor.accentColor),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      descriptor.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descriptor.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
