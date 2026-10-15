import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../core/settings/settings_store.dart';
import 'json_document_controller.dart';

/// Everything the formatter toolbar can ask the page to do.
///
/// A single command channel keeps the toolbar, the keyboard shortcuts and the
/// WebView bridge pointing at one implementation of each action.
enum JsonEditorCommand {
  open,
  save,
  format,
  compact,
  compactAndCopy,
  copy,
  validate,
  sort,
  escape,
  unescape,
  goToLine,
  find,
  collapseAll,
  expandAll,
  clear;

  /// Commands the WebView DOM can request over the JavaScript bridge.
  static JsonEditorCommand? fromId(String id) => switch (id) {
    'save' => JsonEditorCommand.save,
    'format' => JsonEditorCommand.format,
    'compact' => JsonEditorCommand.compact,
    'sort' => JsonEditorCommand.sort,
    'goToLine' => JsonEditorCommand.goToLine,
    _ => null,
  };
}

class JsonEditorToolbar extends StatelessWidget {
  const JsonEditorToolbar({
    super.key,
    required this.controller,
    required this.settings,
    required this.onCommand,
    this.showFoldControls = true,
  });

  final JsonDocumentController controller;
  final SettingsStore settings;
  final ValueChanged<JsonEditorCommand> onCommand;
  final bool showFoldControls;

  @override
  Widget build(BuildContext context) {
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
                    onPressed: () => onCommand(JsonEditorCommand.open),
                  ),
                  _ToolbarButton(
                    tooltip: '保存',
                    icon: Icons.save_outlined,
                    onPressed: () => onCommand(JsonEditorCommand.save),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              _ToolbarGroup(
                children: [
                  _ToolbarButton(
                    tooltip: '格式化',
                    icon: Icons.format_indent_increase_rounded,
                    onPressed: () => onCommand(JsonEditorCommand.format),
                  ),
                  _ToolbarButton(
                    tooltip: '压缩（原地）',
                    icon: Icons.compress_rounded,
                    onPressed: () => onCommand(JsonEditorCommand.compact),
                  ),
                  _ToolbarButton(
                    tooltip: '压缩并复制（不改动编辑器内容）',
                    icon: Icons.content_copy_outlined,
                    onPressed: () =>
                        onCommand(JsonEditorCommand.compactAndCopy),
                  ),
                  _ToolbarButton(
                    tooltip: '复制',
                    icon: Icons.copy_all_rounded,
                    onPressed: () => onCommand(JsonEditorCommand.copy),
                  ),
                ],
              ),
              if (showFoldControls) ...[
                const SizedBox(width: 6),
                _ToolbarGroup(
                  children: [
                    _ToolbarButton(
                      tooltip: '折叠全部',
                      icon: Icons.unfold_less_rounded,
                      onPressed: () => onCommand(JsonEditorCommand.collapseAll),
                    ),
                    _ToolbarButton(
                      tooltip: '展开全部',
                      icon: Icons.unfold_more_rounded,
                      onPressed: () => onCommand(JsonEditorCommand.expandAll),
                    ),
                  ],
                ),
              ],
              const SizedBox(width: 6),
              _ToolbarGroup(
                children: [
                  _ToolbarButton(
                    tooltip: '查找',
                    icon: Icons.search_rounded,
                    onPressed: () => onCommand(JsonEditorCommand.find),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              _ToolbarGroup(children: [_MoreMenu(onSelected: onCommand)]),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.onSelected});

  final ValueChanged<JsonEditorCommand> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: PopupMenuButton<JsonEditorCommand>(
        tooltip: '更多',
        position: PopupMenuPosition.under,
        icon: const Icon(Icons.more_horiz_rounded, size: 20),
        padding: EdgeInsets.zero,
        iconColor: scheme.onSurfaceVariant,
        onSelected: onSelected,
        // Room for the Chinese labels; the default 48px squeezes them.
        constraints: const BoxConstraints(minWidth: 208),
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: JsonEditorCommand.validate,
            child: _MenuItem(icon: Icons.fact_check_outlined, label: '校验 JSON'),
          ),
          PopupMenuItem(
            value: JsonEditorCommand.sort,
            child: _MenuItem(icon: Icons.sort_by_alpha_rounded, label: '按键名排序'),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: JsonEditorCommand.unescape,
            child: _MenuItem(icon: Icons.terminal_rounded, label: '去转义'),
          ),
          PopupMenuItem(
            value: JsonEditorCommand.escape,
            child: _MenuItem(icon: Icons.code_rounded, label: '转义为字符串'),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: JsonEditorCommand.goToLine,
            child: _MenuItem(icon: Icons.my_location_rounded, label: '跳转到行'),
          ),
          PopupMenuItem(
            value: JsonEditorCommand.clear,
            child: _MenuItem(icon: Icons.delete_outline_rounded, label: '清空'),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
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
  const JsonEditorStatusBar({
    super.key,
    required this.controller,
    this.caretLabel,
    this.indentLabel,
    this.onJumpToError,
  });

  final JsonDocumentController controller;

  /// Caret position such as `行 12，列 5`, or null while the editor has none.
  final String? caretLabel;
  final String? indentLabel;

  /// Called when the error text is clicked, to reveal the offending character.
  final VoidCallback? onJumpToError;

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
    final text = controller.text;
    final lineCount = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    final meta = [
      if (controller.repaired) '已自动修复',
      '$lineCount 行',
      ?indentLabel,
      ?caretLabel,
      '${utf8.encode(text).length} B',
    ].join(' · ');
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
              Expanded(child: _buildStatusText(theme, statusText, statusColor)),
              const SizedBox(width: 12),
              Text(
                meta,
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

  Widget _buildStatusText(ThemeData theme, String statusText, Color color) {
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    final onJump = onJumpToError;
    if (controller.status != JsonDocumentStatus.invalid || onJump == null) {
      return Text(statusText, overflow: TextOverflow.ellipsis, style: style);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: '点击跳转到出错位置',
        child: InkWell(
          onTap: onJump,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    statusText,
                    overflow: TextOverflow.ellipsis,
                    style: style?.copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: color,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.my_location_rounded, size: 13, color: color),
              ],
            ),
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
