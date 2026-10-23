import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/desktop/desktop_text_selection.dart';
import '../../core/desktop/web_text_editor.dart';
import '../../core/widgets/mac_ui.dart';
import 'text_compare_controller.dart';
import 'text_compare_indicator.dart';
import 'text_compare_models.dart';

class _CompareChunkAnalyzer implements CodeChunkAnalyzer {
  const _CompareChunkAnalyzer();

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    return [
      for (var index = 0; index < codeLines.length; index++)
        if (codeLines[index].chunkParent)
          // A collapsed line is already a valid folded chunk. Reporting its
          // hidden range again makes re_editor's async analyzer expand it.
          CodeChunk(index, index + 1),
    ];
  }
}

class CompareTextPane extends StatelessWidget {
  const CompareTextPane({
    super.key,
    required this.side,
    required this.controller,
    required this.editor,
    required this.scrollController,
    required this.focusNode,
    required this.emphasized,
    required this.onPaste,
    required this.onFind,
    required this.onEditorPointerDown,
    required this.onChanged,
    required this.useWebEditor,
    required this.webEditorController,
    required this.webController,
    required this.webSelection,
    required this.webHighlights,
    required this.onWebSelectionChanged,
    required this.onWebChanged,
    required this.onWebScrollChanged,
  });

  final TextCompareSide side;
  final TextCompareController controller;
  final CodeLineEditingController editor;
  final CodeScrollController scrollController;
  final FocusNode focusNode;
  final bool emphasized;
  final VoidCallback onPaste;
  final VoidCallback onFind;
  final VoidCallback onEditorPointerDown;
  final ValueChanged<CodeLineEditingValue> onChanged;
  final bool useWebEditor;
  final DesktopWebTextEditorController webEditorController;
  final TextEditingController webController;
  final NativeTextSelection webSelection;
  final List<DesktopTextHighlight> webHighlights;
  final ValueChanged<NativeTextSelection> onWebSelectionChanged;
  final ValueChanged<String> onWebChanged;
  final ValueChanged<int> onWebScrollChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLeft = side == TextCompareSide.left;
    final fileName = isLeft
        ? controller.leftFileName
        : controller.rightFileName;
    final dirty = isLeft ? controller.leftDirty : controller.rightDirty;
    final text = isLeft ? controller.leftText : controller.rightText;
    final lines = isLeft
        ? controller.result?.leftLines ?? const []
        : controller.result?.rightLines ?? const [];
    return MacPanel(
      title: isLeft ? '旧文本' : '新文本',
      icon: isLeft ? Icons.article_outlined : Icons.article_rounded,
      emphasized: emphasized,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Padding(
          padding: const EdgeInsets.only(right: 9),
          child: Text(
            '$fileName${dirty ? ' · 已修改' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall?.copyWith(
              color: dirty ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      footer: Text(
        '${editor.lineCount} 行 · ${text.characters.length} 字符 · ${_formatBytes(utf8.encode(text).length)}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      child: useWebEditor
          ? DesktopWebTextEditor(
              controller: webEditorController,
              text: webController.text,
              selection: webSelection,
              onChanged: onWebChanged,
              onSelectionChanged: onWebSelectionChanged,
              onEditorPointerDown: onEditorPointerDown,
              onFind: onFind,
              highlights: webHighlights,
              backgroundColor: scheme.surfaceContainerLowest,
              textColor: scheme.onSurface,
              isDark: scheme.brightness == Brightness.dark,
              placeholder: isLeft ? '输入或粘贴旧文本' : '输入或粘贴新文本',
              onScrollOffsetChanged: onWebScrollChanged,
              debugLabel: isLeft ? 'text-compare-left' : 'text-compare-right',
              autofocus: isLeft,
              fontSize: 13,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            )
          : CodeEditor(
              // Keep the editor state mounted while diff metadata changes.
              // Re-mounting CodeEditor resets its internal input connection
              // and can make the caret/focus look out of sync with the pane
              // that will receive the next paste.
              controller: editor,
              scrollController: scrollController,
              focusNode: focusNode,
              shortcutOverrideActions: {
                CodeShortcutPasteIntent:
                    CallbackAction<CodeShortcutPasteIntent>(
                      onInvoke: (_) => onPaste(),
                    ),
              },
              autofocus: false,
              wordWrap: false,
              autocompleteSymbols: false,
              chunkAnalyzer: const _CompareChunkAnalyzer(),
              onChanged: onChanged,
              hint: isLeft ? '输入或粘贴旧文本' : '输入或粘贴新文本',
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              style: CodeEditorStyle(
                fontSize: 13,
                fontHeight: 1.55,
                fontFamily: 'Menlo',
                fontFamilyFallback: const ['Consolas', 'monospace'],
                backgroundColor: scheme.surfaceContainerLowest,
                cursorColor: scheme.primary,
                cursorLineColor: scheme.primary.withAlpha(24),
              ),
              indicatorBuilder:
                  (context, editingController, chunkController, notifier) {
                    return TextCompareIndicator(
                      controller: editingController,
                      notifier: notifier,
                      lines: lines,
                    );
                  },
              leadingDivider: Container(width: 1, color: scheme.outlineVariant),
            ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
}
