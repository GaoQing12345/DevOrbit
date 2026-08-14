import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import 'text_compare_controller.dart';
import 'text_compare_indicator.dart';
import 'text_compare_models.dart';

class TextComparePage extends StatefulWidget {
  const TextComparePage({super.key, required this.controller});

  final TextCompareController controller;

  @override
  State<TextComparePage> createState() => _TextComparePageState();
}

class _TextComparePageState extends State<TextComparePage> {
  late final CodeLineEditingController _leftEditor;
  late final CodeLineEditingController _rightEditor;
  final _leftFocusNode = FocusNode();
  final _rightFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _leftEditor = _createEditor(TextCompareSide.left);
    _rightEditor = _createEditor(TextCompareSide.right);
    widget.controller.addListener(_syncFromController);
    _leftFocusNode.addListener(_handleFocusChange);
    _rightFocusNode.addListener(_handleFocusChange);
  }

  CodeLineEditingController _createEditor(TextCompareSide side) {
    final text = side == TextCompareSide.left
        ? widget.controller.leftText
        : widget.controller.rightText;
    return CodeLineEditingController(
      codeLines: CodeLines.fromText(text),
      spanBuilder:
          ({
            required context,
            required index,
            required codeLine,
            required textSpan,
            required style,
          }) => _buildLineSpan(
            context: context,
            side: side,
            index: index,
            text: codeLine.text,
            style: style,
          ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _leftFocusNode.removeListener(_handleFocusChange);
    _rightFocusNode.removeListener(_handleFocusChange);
    _leftEditor.dispose();
    _rightEditor.dispose();
    _leftFocusNode.dispose();
    _rightFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  void _syncFromController() {
    if (_leftEditor.text != widget.controller.leftText) {
      _leftEditor.text = widget.controller.leftText;
    }
    if (_rightEditor.text != widget.controller.rightText) {
      _rightEditor.text = widget.controller.rightText;
    }
    if (mounted) setState(() {});
  }

  Future<void> _openFile(TextCompareSide side) async {
    final file = await openFile();
    if (file == null) return;
    final loaded = await widget.controller.loadFile(side, file);
    if (!loaded && mounted && widget.controller.errorMessage != null) {
      _showMessage(widget.controller.errorMessage!);
    }
  }

  Future<void> _copySummary() async {
    final summary = widget.controller.buildSummary();
    if (summary.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: summary));
    if (mounted) _showMessage('比对摘要已复制');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  TextSpan _buildLineSpan({
    required BuildContext context,
    required TextCompareSide side,
    required int index,
    required String text,
    required TextStyle style,
  }) {
    final result = widget.controller.result;
    final lines = side == TextCompareSide.left
        ? result?.leftLines
        : result?.rightLines;
    if (lines == null || index >= lines.length) {
      return TextSpan(text: text, style: style);
    }
    final line = lines[index];
    final colors = _diffColors(context, side, line.status);
    if (line.ranges.isEmpty) {
      return TextSpan(
        text: text,
        style: style.copyWith(backgroundColor: colors.line),
      );
    }
    final children = <TextSpan>[];
    var offset = 0;
    for (final range in line.ranges) {
      if (range.start > offset) {
        children.add(TextSpan(text: text.substring(offset, range.start)));
      }
      children.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: style.copyWith(backgroundColor: colors.character),
        ),
      );
      offset = range.end;
    }
    if (offset < text.length) {
      children.add(TextSpan(text: text.substring(offset)));
    }
    return TextSpan(
      style: style.copyWith(backgroundColor: colors.line),
      children: children,
    );
  }

  ({Color line, Color character}) _diffColors(
    BuildContext context,
    TextCompareSide side,
    TextDiffLineStatus status,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = switch (status) {
      TextDiffLineStatus.added => Color.fromARGB(dark ? 66 : 38, 46, 155, 99),
      TextDiffLineStatus.removed => Color.fromARGB(dark ? 66 : 34, 204, 74, 82),
      TextDiffLineStatus.modified => Color.fromARGB(
        dark ? 64 : 34,
        209,
        138,
        22,
      ),
      TextDiffLineStatus.unchanged => Colors.transparent,
    };
    final character = side == TextCompareSide.left
        ? Color.fromARGB(dark ? 138 : 86, 204, 74, 82)
        : Color.fromARGB(dark ? 132 : 78, 46, 155, 99);
    return (line: line, character: character);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            widget.controller.compare,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            widget.controller.compare,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: Column(
            children: [
              _CompareToolbar(
                controller: widget.controller,
                onOpenLeft: () => _openFile(TextCompareSide.left),
                onOpenRight: () => _openFile(TextCompareSide.right),
                onCopySummary: _copySummary,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TextPane(
                          side: TextCompareSide.left,
                          controller: widget.controller,
                          editor: _leftEditor,
                          focusNode: _leftFocusNode,
                          emphasized: _leftFocusNode.hasFocus,
                          onChanged: (_) =>
                              widget.controller.updateLeft(_leftEditor.text),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TextPane(
                          side: TextCompareSide.right,
                          controller: widget.controller,
                          editor: _rightEditor,
                          focusNode: _rightFocusNode,
                          emphasized: _rightFocusNode.hasFocus,
                          onChanged: (_) =>
                              widget.controller.updateRight(_rightEditor.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _CompareStatusBar(controller: widget.controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompareToolbar extends StatelessWidget {
  const _CompareToolbar({
    required this.controller,
    required this.onOpenLeft,
    required this.onOpenRight,
    required this.onCopySummary,
  });

  final TextCompareController controller;
  final VoidCallback onOpenLeft;
  final VoidCallback onOpenRight;
  final VoidCallback onCopySummary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FileButton(label: '左侧文件', onPressed: onOpenLeft),
            _FileButton(label: '右侧文件', onPressed: onOpenRight),
            _OptionToggle(
              label: '忽略大小写',
              value: controller.options.ignoreCase,
              onChanged: controller.updateIgnoreCase,
            ),
            _OptionToggle(
              label: '忽略行尾空白',
              value: controller.options.ignoreTrailingWhitespace,
              onChanged: controller.updateIgnoreTrailingWhitespace,
            ),
            FilledButton.icon(
              onPressed: controller.canCompare ? controller.compare : null,
              icon: controller.isComparing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.difference_rounded),
              label: Text(controller.isComparing ? '比对中' : '开始比对'),
            ),
            _ToolbarAction(
              tooltip: '交换左右文本',
              icon: Icons.swap_horiz_rounded,
              onPressed:
                  controller.leftText.isEmpty && controller.rightText.isEmpty
                  ? null
                  : controller.swap,
            ),
            _ToolbarAction(
              tooltip: '清空',
              icon: Icons.delete_outline_rounded,
              onPressed:
                  controller.leftText.isEmpty && controller.rightText.isEmpty
                  ? null
                  : controller.clear,
            ),
            _ToolbarAction(
              tooltip: '复制比对摘要',
              icon: Icons.content_copy_rounded,
              onPressed: controller.canCopySummary ? onCopySummary : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FileButton extends StatelessWidget {
  const _FileButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.folder_open_rounded),
      label: Text(label),
    );
  }
}

class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      checked: value,
      child: FilterChip(
        selected: value,
        showCheckmark: true,
        label: Text(label),
        onSelected: onChanged,
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon));
  }
}

class _TextPane extends StatelessWidget {
  const _TextPane({
    required this.side,
    required this.controller,
    required this.editor,
    required this.focusNode,
    required this.emphasized,
    required this.onChanged,
  });

  final TextCompareSide side;
  final TextCompareController controller;
  final CodeLineEditingController editor;
  final FocusNode focusNode;
  final bool emphasized;
  final ValueChanged<CodeLineEditingValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLeft = side == TextCompareSide.left;
    final fileName = isLeft
        ? controller.leftFileName
        : controller.rightFileName;
    final dirty = isLeft ? controller.leftDirty : controller.rightDirty;
    final text = isLeft ? controller.leftText : controller.rightText;
    final lines = isLeft
        ? controller.result?.leftLines ?? const []
        : controller.result?.rightLines ?? const [];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(
          color: emphasized ? scheme.primary : scheme.outlineVariant,
          width: emphasized ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isLeft ? Icons.article_outlined : Icons.article_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isLeft ? '旧文本' : '新文本',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$fileName${dirty ? ' · 已修改' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: dirty ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CodeEditor(
                key: ValueKey('${side.name}-${controller.highlightRevision}'),
                controller: editor,
                focusNode: focusNode,
                autofocus: false,
                wordWrap: false,
                autocompleteSymbols: false,
                chunkAnalyzer: const NonCodeChunkAnalyzer(),
                onChanged: onChanged,
                hint: isLeft ? '输入或粘贴旧文本' : '输入或粘贴新文本',
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                style: CodeEditorStyle(
                  fontSize: 14,
                  fontHeight: 1.55,
                  fontFamily: 'Menlo',
                  fontFamilyFallback: const ['Consolas', 'monospace'],
                  backgroundColor: scheme.surfaceContainerLowest,
                  cursorLineColor: scheme.primary.withAlpha(20),
                ),
                indicatorBuilder:
                    (context, editingController, chunkController, notifier) {
                      return TextCompareIndicator(
                        controller: editingController,
                        notifier: notifier,
                        lines: lines,
                      );
                    },
                leadingDivider: Container(
                  width: 1,
                  color: scheme.outlineVariant,
                ),
              ),
            ),
            Container(
              height: 34,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Text(
                '${editor.lineCount} 行 · ${text.characters.length} 字符 · ${_formatBytes(utf8.encode(text).length)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareStatusBar extends StatelessWidget {
  const _CompareStatusBar({required this.controller});

  final TextCompareController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = controller.result;
    final text = switch (controller.status) {
      TextCompareStatus.idle => '准备就绪',
      TextCompareStatus.comparing => '正在比对文本',
      TextCompareStatus.unchanged => '两侧文本一致',
      TextCompareStatus.changed =>
        '新增 ${result?.addedCount ?? 0} 行 · 删除 ${result?.removedCount ?? 0} 行 · 修改 ${result?.modifiedCount ?? 0} 行',
      TextCompareStatus.stale => '内容已更改，请重新比对',
      TextCompareStatus.error => controller.errorMessage ?? '比对失败',
    };
    final color = switch (controller.status) {
      TextCompareStatus.error => scheme.error,
      TextCompareStatus.changed ||
      TextCompareStatus.stale => const Color(0xFFD18A16),
      TextCompareStatus.unchanged => const Color(0xFF2E9B63),
      _ => scheme.onSurfaceVariant,
    };
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            controller.isComparing
                ? Icons.sync_rounded
                : Icons.info_outline_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
          Text(
            '上限 10 MiB / 侧',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}
