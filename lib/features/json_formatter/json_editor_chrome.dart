import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../core/settings/settings_store.dart';
import 'json_document_controller.dart';
import 'json_transformer.dart';

class JsonEditorToolbar extends StatelessWidget {
  const JsonEditorToolbar({
    super.key,
    required this.controller,
    required this.settings,
    required this.onOpen,
    required this.onSave,
    required this.onCopy,
    required this.onCompactAndCopy,
    required this.onFind,
    required this.onCollapseAll,
    required this.onExpandAll,
  });

  final JsonDocumentController controller;
  final SettingsStore settings;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onCopy;
  final VoidCallback onCompactAndCopy;
  final VoidCallback onFind;
  final VoidCallback onCollapseAll;
  final VoidCallback onExpandAll;

  @override
  Widget build(BuildContext context) {
    final indent = settings.value.indentSize;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              _ToolbarGroup(
                children: [
                  _ToolbarButton(
                    tooltip: '打开 JSON',
                    icon: Icons.folder_open_rounded,
                    onPressed: onOpen,
                  ),
                  _ToolbarButton(
                    tooltip: '保存',
                    icon: Icons.save_outlined,
                    onPressed: onSave,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _ToolbarGroup(
                children: [
                  _ToolbarButton(
                    tooltip: '格式化',
                    icon: Icons.format_indent_increase_rounded,
                    onPressed: () {
                      controller.transform(JsonTransformMode.format, indent);
                    },
                  ),
                  _ToolbarButton(
                    tooltip: '压缩并复制',
                    icon: Icons.compress_rounded,
                    onPressed: onCompactAndCopy,
                  ),
                  _ToolbarButton(
                    tooltip: '复制',
                    icon: Icons.content_copy_rounded,
                    onPressed: onCopy,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _ToolbarGroup(
                children: [
                  _ToolbarButton(
                    tooltip: '折叠全部',
                    icon: Icons.unfold_less_rounded,
                    onPressed: onCollapseAll,
                  ),
                  _ToolbarButton(
                    tooltip: '展开全部',
                    icon: Icons.unfold_more_rounded,
                    onPressed: onExpandAll,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _ToolbarGroup(
                children: [
                  _ToolbarButton(
                    tooltip: '查找',
                    icon: Icons.search_rounded,
                    onPressed: onFind,
                  ),
                ],
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  controller.filePath == null
                      ? '未命名.json'
                      : path.basename(controller.filePath!),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (controller.isDirty) ...[
                const SizedBox(width: 6),
                Icon(Icons.circle, size: 6, color: scheme.primary),
              ],
              const SizedBox(width: 8),
              _ToolbarButton(
                tooltip: '清空',
                icon: Icons.delete_outline_rounded,
                onPressed: controller.clear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarGroup extends StatelessWidget {
  const _ToolbarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class JsonEditorStatusBar extends StatelessWidget {
  const JsonEditorStatusBar({super.key, required this.controller});

  final JsonDocumentController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issue = controller.issue;
    final statusText = switch (controller.status) {
      JsonDocumentStatus.empty => '等待输入',
      JsonDocumentStatus.validating => '正在校验',
      JsonDocumentStatus.valid => 'JSON 有效',
      JsonDocumentStatus.invalid =>
        '第 ${issue?.line ?? 1} 行，第 ${issue?.column ?? 1} 列：${issue?.message}',
    };
    final statusColor = controller.status == JsonDocumentStatus.invalid
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(
                controller.status == JsonDocumentStatus.invalid
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 15,
                color: statusColor,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  statusText,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
              Text(
                '${utf8.encode(controller.text).length} B',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
  }
}
