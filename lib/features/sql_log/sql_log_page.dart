import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/desktop/desktop_clipboard_focus_restorer.dart';
import 'sql_log_controller.dart';
import 'sql_log_converter.dart';

class SqlLogPage extends StatefulWidget {
  const SqlLogPage({super.key, this.controller});

  final SqlLogController? controller;

  @override
  State<SqlLogPage> createState() => _SqlLogPageState();
}

class _SqlLogPageState extends State<SqlLogPage> {
  late final SqlLogController _controller;
  late final bool _ownsController;
  late final TextEditingController _inputController;
  late final TextEditingController _outputController;
  final _inputFocusNode = FocusNode();
  late final DesktopClipboardFocusRestorer _focusRestorer;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? SqlLogController();
    _inputController = TextEditingController(text: _controller.sourceText);
    _outputController = TextEditingController(text: _controller.result.output);
    _controller.addListener(_syncFromController);
    _focusRestorer = DesktopClipboardFocusRestorer(
      targets: [
        TextEditingClipboardTarget(
          controller: _inputController,
          focusNode: _inputFocusNode,
          onChanged: _controller.updateSource,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _focusRestorer.dispose();
    _controller.removeListener(_syncFromController);
    if (_ownsController) _controller.dispose();
    _inputController.dispose();
    _outputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _syncFromController() {
    if (!mounted) return;
    if (_inputController.text != _controller.sourceText) {
      final text = _controller.sourceText;
      _inputController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    if (_outputController.text != _controller.result.output) {
      _outputController.text = _controller.result.output;
    }
    setState(() {});
  }

  Future<void> _copyOutput() async {
    final output = _controller.result.output;
    if (output.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: output));
    } on PlatformException {
      if (mounted) _showMessage('复制失败');
      return;
    }
    if (mounted) _showMessage('SQL 已复制');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    _focusRestorer.active = Visibility.of(context);
    final result = _controller.result;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          _Toolbar(
            dialect: _controller.dialect,
            canCopy: result.output.isNotEmpty,
            onDialectChanged: _controller.setDialect,
            onConvert: _controller.convertNow,
            onCopy: _copyOutput,
            onClear: _controller.clear,
          ),
          _StatusBar(
            result: result,
            hasInput: _controller.sourceText.isNotEmpty,
          ),
          if (result.allWarnings.isNotEmpty)
            _WarningBanner(messages: result.allWarnings),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final input = _EditorPanel(
                    title: 'MyBatis 日志',
                    icon: Icons.article_outlined,
                    trailing: IconButton(
                      tooltip: '粘贴',
                      onPressed: _focusRestorer.pasteFocusedTarget,
                      icon: const Icon(Icons.content_paste_rounded, size: 19),
                    ),
                    child: TextField(
                      key: const ValueKey('sql-log-input'),
                      controller: _inputController,
                      focusNode: _inputFocusNode,
                      autofocus: true,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      onChanged: _controller.updateSource,
                      contextMenuBuilder: (context, editableTextState) =>
                          AdaptiveTextSelectionToolbar.editableText(
                            editableTextState: editableTextState,
                          ),
                      style: _editorTextStyle(context),
                      decoration: _editorDecoration(context),
                    ),
                  );
                  final output = _EditorPanel(
                    title: '格式化 SQL',
                    icon: Icons.data_object_rounded,
                    trailing: IconButton(
                      tooltip: '复制全部 SQL',
                      onPressed: result.output.isEmpty ? null : _copyOutput,
                      icon: const Icon(Icons.copy_rounded, size: 19),
                    ),
                    child: TextField(
                      key: const ValueKey('sql-log-output'),
                      controller: _outputController,
                      readOnly: true,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      contextMenuBuilder: (context, editableTextState) =>
                          AdaptiveTextSelectionToolbar.editableText(
                            editableTextState: editableTextState,
                          ),
                      style: _editorTextStyle(context),
                      decoration: _editorDecoration(context),
                    ),
                  );
                  if (constraints.maxWidth >= 820) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: input),
                        const SizedBox(width: 12),
                        Expanded(child: output),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: input),
                      const SizedBox(height: 12),
                      Expanded(child: output),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _editorTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['Consolas', 'monospace'],
      height: 1.55,
    );
  }

  InputDecoration _editorDecoration(BuildContext context) {
    return InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.all(14),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.dialect,
    required this.canCopy,
    required this.onDialectChanged,
    required this.onConvert,
    required this.onCopy,
    required this.onClear,
  });

  final SqlLogDialect dialect;
  final bool canCopy;
  final ValueChanged<SqlLogDialect> onDialectChanged;
  final VoidCallback onConvert;
  final VoidCallback onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.storage_rounded, size: 21, color: scheme.primary),
          const SizedBox(width: 10),
          Text(
            'SQL 日志还原',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          SizedBox(
            width: 142,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SqlLogDialect>(
                value: dialect,
                isExpanded: true,
                borderRadius: BorderRadius.circular(6),
                onChanged: (value) {
                  if (value != null) onDialectChanged(value);
                },
                items: [
                  for (final value in SqlLogDialect.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onConvert,
            icon: const Icon(Icons.play_arrow_rounded, size: 19),
            label: const Text('转换'),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '复制全部 SQL',
            onPressed: canCopy ? onCopy : null,
            icon: const Icon(Icons.copy_rounded, size: 19),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.result, required this.hasInput});

  final SqlLogConversionResult result;
  final bool hasInput;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholderCount = result.statements.fold(
      0,
      (count, statement) => count + statement.placeholderCount,
    );
    final substitutedCount = result.statements.fold(
      0,
      (count, statement) => count + statement.substitutedCount,
    );
    final status = result.statements.isEmpty
        ? (hasInput ? '未识别 SQL' : '未输入日志')
        : '已识别 ${result.statements.length} 条 SQL';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: scheme.surfaceContainerLowest,
      child: Wrap(
        spacing: 18,
        runSpacing: 4,
        children: [
          _StatusItem(icon: Icons.check_circle_outline_rounded, text: status),
          if (placeholderCount > 0)
            _StatusItem(
              icon: Icons.find_replace_rounded,
              text: '已替换 $substitutedCount / $placeholderCount 个参数',
            ),
          if (result.warningCount > 0)
            _StatusItem(
              icon: Icons.warning_amber_rounded,
              text: '${result.warningCount} 条提示',
              color: scheme.tertiary,
            ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: foreground),
        const SizedBox(width: 5),
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: foreground),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = messages.take(2).join('\n');
    final remaining = messages.length - 2;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withAlpha(110),
        border: Border.all(color: scheme.tertiary.withAlpha(100)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: scheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              remaining > 0 ? '$visible\n另有 $remaining 条提示' : visible,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorPanel extends StatelessWidget {
  const _EditorPanel({
    required this.title,
    required this.icon,
    required this.trailing,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ColoredBox(
              color: scheme.surfaceContainerLow,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  trailing,
                  const SizedBox(width: 2),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(child: child),
        ],
      ),
    );
  }
}
