import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

class JsonFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const JsonFindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  static const _panelWidth = 510.0;
  static const _rowHeight = 40.0;

  final CodeFindController controller;
  final bool readOnly;

  @override
  Size get preferredSize {
    final value = controller.value;
    if (value == null) return Size.zero;
    return Size.fromHeight(value.replaceMode ? 92 : 52);
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topRight,
      child: Container(
        width: _panelWidth,
        height: preferredSize.height,
        margin: const EdgeInsets.only(top: 10, right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            _FindRow(controller: controller, value: value),
            if (value.replaceMode)
              _ReplaceRow(controller: controller, readOnly: readOnly),
          ],
        ),
      ),
    );
  }
}

class _FindRow extends StatelessWidget {
  const _FindRow({required this.controller, required this.value});

  final CodeFindController controller;
  final CodeFindValue value;

  @override
  Widget build(BuildContext context) {
    final result = value.result;
    final resultText = result == null
        ? '0/0'
        : '${result.index + 1}/${result.matches.length}';
    return SizedBox(
      height: JsonFindPanel._rowHeight,
      child: Row(
        children: [
          _PanelIconButton(
            tooltip: value.replaceMode ? '隐藏替换' : '显示替换',
            icon: value.replaceMode
                ? Icons.keyboard_arrow_down_rounded
                : Icons.keyboard_arrow_right_rounded,
            onPressed: controller.toggleMode,
          ),
          Expanded(
            child: _PanelTextField(
              key: const ValueKey('json-find-input'),
              controller: controller.findInputController,
              focusNode: controller.findInputFocusNode,
              hintText: '查找',
              onSubmitted: (_) => controller.nextMatch(),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              resultText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _PanelIconButton(
            tooltip: '上一个',
            icon: Icons.keyboard_arrow_up_rounded,
            onPressed: result == null ? null : controller.previousMatch,
          ),
          _PanelIconButton(
            tooltip: '下一个',
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: result == null ? null : controller.nextMatch,
          ),
          _PanelIconButton(
            tooltip: '关闭查找',
            icon: Icons.close_rounded,
            onPressed: controller.close,
          ),
        ],
      ),
    );
  }
}

class _ReplaceRow extends StatelessWidget {
  const _ReplaceRow({required this.controller, required this.readOnly});

  final CodeFindController controller;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final canReplace = !readOnly && controller.value?.result != null;
    return SizedBox(
      height: JsonFindPanel._rowHeight,
      child: Row(
        children: [
          const SizedBox(width: 36),
          Expanded(
            child: _PanelTextField(
              key: const ValueKey('json-replace-input'),
              controller: controller.replaceInputController,
              focusNode: controller.replaceInputFocusNode,
              hintText: '替换为',
              onSubmitted: (_) => controller.replaceMatch(),
            ),
          ),
          _PanelIconButton(
            tooltip: '替换',
            icon: Icons.find_replace_rounded,
            onPressed: canReplace ? controller.replaceMatch : null,
          ),
          _PanelIconButton(
            tooltip: '全部替换',
            icon: Icons.done_all_rounded,
            onPressed: canReplace ? controller.replaceAllMatches : null,
          ),
          const SizedBox(width: 84),
        ],
      ),
    );
  }
}

class _PanelTextField extends StatelessWidget {
  const _PanelTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _pasteClipboard,
        if (defaultTargetPlatform == TargetPlatform.macOS)
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              _pasteClipboard,
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: 1,
        onSubmitted: onSubmitted,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: hintText,
          isDense: true,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 9,
          ),
        ),
      ),
    );
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final selection = controller.selection;
    final start = _validOffset(selection.start, controller.text.length);
    final end = _validOffset(selection.end, controller.text.length);
    final nextText = controller.text.replaceRange(start, end, text);
    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    focusNode.requestFocus();
  }

  int _validOffset(int offset, int textLength) {
    if (offset < 0 || offset > textLength) return textLength;
    return offset;
  }
}

class _PanelIconButton extends StatelessWidget {
  const _PanelIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
  }
}
