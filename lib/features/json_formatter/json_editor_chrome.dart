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
    final fileName = controller.filePath == null
        ? '未命名.json'
        : path.basename(controller.filePath!);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  Icons.data_object_rounded,
                  size: 19,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 154),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      controller.isDirty ? '有未保存的更改' : 'JSON 文档',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: controller.isDirty
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
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
              const SizedBox(width: 6),
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
              const SizedBox(width: 6),
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
              const SizedBox(width: 6),
              _ToolbarGroup(
                children: [
                  _ToolbarButton(
                    tooltip: '查找',
                    icon: Icons.search_rounded,
                    onPressed: onFind,
                  ),
                ],
              ),
              const SizedBox(width: 6),
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
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
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
    final isInvalid = controller.status == JsonDocumentStatus.invalid;
    final isValid = controller.status == JsonDocumentStatus.valid;
    final statusColor = isInvalid
        ? theme.colorScheme.error
        : isValid
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
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
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
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
