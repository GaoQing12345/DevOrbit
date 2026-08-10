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
  });

  final JsonDocumentController controller;
  final SettingsStore settings;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final indent = settings.value.indentSize;
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
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
            const VerticalDivider(indent: 14, endIndent: 14),
            _ToolbarButton(
              tooltip: '格式化',
              icon: Icons.format_indent_increase_rounded,
              onPressed: () {
                controller.transform(JsonTransformMode.format, indent);
              },
            ),
            _ToolbarButton(
              tooltip: '压缩',
              icon: Icons.compress_rounded,
              onPressed: () {
                controller.transform(JsonTransformMode.compact, indent);
              },
            ),
            _ToolbarButton(
              tooltip: '复制',
              icon: Icons.content_copy_rounded,
              onPressed: onCopy,
            ),
            const Spacer(),
            Text(
              controller.filePath == null
                  ? '未命名.json'
                  : path.basename(controller.filePath!),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (controller.isDirty)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.circle, size: 7),
              ),
            const SizedBox(width: 8),
            _ToolbarButton(
              tooltip: '清空',
              icon: Icons.delete_outline_rounded,
              onPressed: controller.clear,
            ),
          ],
        ),
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
    final statusColor = controller.status == JsonDocumentStatus.invalid
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 36,
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
                style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
              ),
            ),
            Text(
              '${utf8.encode(controller.text).length} B',
              style: theme.textTheme.bodySmall,
            ),
          ],
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
    );
  }
}
