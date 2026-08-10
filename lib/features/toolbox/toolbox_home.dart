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
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      children: [
        Text('工具箱', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          '已安装 ${registry.modules.length} 个工具',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
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
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: descriptor.accentColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(descriptor.icon, color: descriptor.accentColor),
              ),
              const SizedBox(width: 16),
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
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
