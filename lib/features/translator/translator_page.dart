import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/desktop/desktop_clipboard_focus_restorer.dart';
import '../../core/desktop/desktop_window_shell.dart';
import 'translation_language.dart';
import 'translator_controller.dart';

class TranslatorPage extends StatefulWidget {
  const TranslatorPage({super.key, required this.controller, this.initialText});

  final TranslatorController controller;
  final String? initialText;

  @override
  State<TranslatorPage> createState() => _TranslatorPageState();
}

class _TranslatorPageState extends State<TranslatorPage> {
  late final TextEditingController _sourceController;
  final _sourceFocusNode = FocusNode();
  late final DesktopClipboardFocusRestorer _focusRestorer;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _sourceController = TextEditingController(
      text: widget.initialText ?? widget.controller.sourceText,
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _focusRestorer = DesktopClipboardFocusRestorer(
      targets: [
        TextEditingClipboardTarget(
          controller: _sourceController,
          focusNode: _sourceFocusNode,
          onChanged: widget.controller.updateSource,
        ),
      ],
    );
    widget.controller.addListener(_syncFromController);
    _sourceFocusNode.addListener(_handleFocusChange);
    if (_sourceController.text != widget.controller.sourceText) {
      widget.controller.updateSource(_sourceController.text);
    }
    widget.controller.initialize().whenComplete(() {
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _focusRestorer.dispose();
    _sourceFocusNode.removeListener(_handleFocusChange);
    _sourceController.dispose();
    _sourceFocusNode.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !widget.controller.isTranslating) {
      return false;
    }
    DesktopEscapeCloseRegion.consumeCurrentEscape();
    widget.controller.cancel();
    return true;
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  void _syncFromController() {
    if (_sourceController.text != widget.controller.sourceText) {
      _sourceController.value = TextEditingValue(
        text: widget.controller.sourceText,
        selection: TextSelection.collapsed(
          offset: widget.controller.sourceText.length,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _copyResult() async {
    if (widget.controller.translatedText.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: widget.controller.translatedText),
    );
    if (mounted) _showMessage('译文已复制');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _configureApiKey() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ApiKeyDialog(controller: widget.controller),
    );
    if (saved == true && mounted) _showMessage('DeepL API Key 已保存');
  }

  @override
  Widget build(BuildContext context) {
    _focusRestorer.active = Visibility.of(context);
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, meta: true):
          widget.controller.translate,
      const SingleActivator(LogicalKeyboardKey.enter, control: true):
          widget.controller.translate,
    };
    return CallbackShortcuts(
      bindings: shortcuts,
      child: DesktopClipboardPasteRegion(
        onPaste: _focusRestorer.pasteFocusedTarget,
        child: Focus(
          autofocus: true,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Column(
              children: [
                _Toolbar(
                  controller: widget.controller,
                  initialized: _initialized,
                  onConfigureApiKey: _configureApiKey,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final horizontal = constraints.maxWidth >= 720;
                        final source = Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (_) {
                            if (!_sourceFocusNode.hasFocus) {
                              _sourceFocusNode.requestFocus();
                            }
                          },
                          child: _TranslationPane(
                            title: '原文',
                            footer: '${widget.controller.sourceText.length} 字符',
                            icon: Icons.edit_note_rounded,
                            emphasized: _sourceFocusNode.hasFocus,
                            child: TextField(
                              key: const ValueKey('translator-source'),
                              controller: _sourceController,
                              focusNode: _sourceFocusNode,
                              autofocus: true,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.65,
                              ),
                              decoration: const InputDecoration(
                                hintText: '输入或粘贴文本',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: EdgeInsets.all(18),
                              ),
                              onChanged: widget.controller.updateSource,
                            ),
                          ),
                        );
                        final result = _TranslationPane(
                          title: _resultTitle(),
                          icon: Icons.translate_rounded,
                          emphasized:
                              widget.controller.translatedText.isNotEmpty,
                          footer: widget.controller.translatedText.isEmpty
                              ? ''
                              : '${widget.controller.translatedText.length} 字符',
                          trailing: IconButton(
                            tooltip: '复制译文',
                            onPressed: widget.controller.translatedText.isEmpty
                                ? null
                                : _copyResult,
                            icon: const Icon(Icons.copy_rounded, size: 19),
                          ),
                          child: _TranslationResult(
                            controller: widget.controller,
                          ),
                        );
                        if (!horizontal) {
                          return Column(
                            children: [
                              Expanded(child: source),
                              const SizedBox(height: 12),
                              Expanded(child: result),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: source),
                            const SizedBox(width: 12),
                            Expanded(child: result),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                _StatusBar(controller: widget.controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _resultTitle() {
    final detected = widget.controller.detectedSourceLanguage;
    if (detected == null) return '译文';
    return '译文 · 检测为 ${translationLanguageLabel(detected)}';
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.initialized,
    required this.onConfigureApiKey,
  });

  final TranslatorController controller;
  final bool initialized;
  final VoidCallback onConfigureApiKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            const _LanguageField(
              label: '自动检测',
              icon: Icons.auto_awesome_rounded,
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '交换原文和译文',
              onPressed:
                  controller.translatedText.isEmpty ||
                      controller.detectedSourceLanguage == null
                  ? null
                  : controller.swap,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
            const SizedBox(width: 8),
            DropdownMenu<String>(
              key: ValueKey(controller.targetLanguage),
              width: 170,
              initialSelection: controller.targetLanguage,
              enableFilter: true,
              label: const Text('翻译为'),
              dropdownMenuEntries: [
                for (final language in translationLanguages)
                  DropdownMenuEntry(
                    value: language.code,
                    label: language.label,
                  ),
              ],
              onSelected: (value) {
                if (value != null) controller.updateTargetLanguage(value);
              },
            ),
            const Spacer(),
            if (controller.isTranslating)
              OutlinedButton.icon(
                onPressed: controller.cancel,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('取消'),
              )
            else
              FilledButton.icon(
                onPressed: controller.sourceText.trim().isEmpty
                    ? null
                    : controller.translate,
                icon: const Icon(Icons.translate_rounded),
                label: const Text('翻译'),
              ),
            const SizedBox(width: 10),
            Container(width: 1, height: 24, color: scheme.outlineVariant),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '清空',
              onPressed:
                  controller.sourceText.isEmpty &&
                      controller.translatedText.isEmpty
                  ? null
                  : controller.clear,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            IconButton(
              tooltip: controller.hasApiKey
                  ? '更改 DeepL API Key'
                  : '配置 DeepL API Key',
              onPressed: initialized ? onConfigureApiKey : null,
              icon: Icon(
                controller.hasApiKey
                    ? Icons.key_rounded
                    : Icons.key_off_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageField extends StatelessWidget {
  const _LanguageField({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _TranslationPane extends StatelessWidget {
  const _TranslationPane({
    required this.title,
    required this.footer,
    required this.icon,
    required this.emphasized,
    required this.child,
    this.trailing,
  });

  final String title;
  final String footer;
  final IconData icon;
  final bool emphasized;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(
          color: emphasized ? scheme.primary : scheme.outlineVariant,
          width: emphasized ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withAlpha(18),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 7),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: emphasized
                            ? scheme.primaryContainer
                            : scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        icon,
                        size: 16,
                        color: emphasized
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: ColoredBox(
                color: scheme.brightness == Brightness.dark
                    ? scheme.surfaceContainerLowest
                    : const Color(0xFFFBFCFC),
                child: child,
              ),
            ),
            if (footer.isNotEmpty) ...[
              Divider(height: 1, color: scheme.outlineVariant),
              SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      footer,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TranslationResult extends StatelessWidget {
  const _TranslationResult({required this.controller});

  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isTranslating && controller.translatedText.isEmpty) {
      return const _TranslationSkeleton();
    }
    if (controller.translatedText.isEmpty) {
      return const _CenteredState(
        icon: Icon(Icons.notes_rounded, size: 22),
        text: '译文会显示在这里',
      );
    }
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            controller.translatedText,
            style: const TextStyle(fontSize: 15, height: 1.65),
          ),
        ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.icon, required this.text});

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: color),
              child: icon,
            ),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

class _TranslationSkeleton extends StatelessWidget {
  const _TranslationSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 22),
          for (final width in [0.88, 0.72, 0.81, 0.56]) ...[
            FractionallySizedBox(
              widthFactor: width,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 13),
          ],
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final TranslatorController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            controller.errorMessage == null
                ? controller.hasApiKey
                      ? Icons.lock_outline_rounded
                      : Icons.key_off_rounded
                : Icons.error_outline_rounded,
            size: 16,
            color: controller.errorMessage == null
                ? scheme.onSurfaceVariant
                : scheme.error,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              controller.errorMessage ??
                  (controller.hasApiKey
                      ? 'DeepL API Free'
                      : '尚未配置 DeepL API Key'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: controller.errorMessage == null
                    ? scheme.onSurfaceVariant
                    : scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog({required this.controller});

  final TranslatorController controller;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  final _keyController = TextEditingController();
  final _keyFocusNode = FocusNode();
  late final DesktopClipboardFocusRestorer _focusRestorer;
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focusRestorer = DesktopClipboardFocusRestorer(
      targets: [
        TextEditingClipboardTarget(
          controller: _keyController,
          focusNode: _keyFocusNode,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _focusRestorer.dispose();
    _keyController.dispose();
    _keyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _keyController.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '请输入 DeepL API Key');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveApiKey(value);
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '无法保存 API Key';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _focusRestorer.active = Visibility.of(context);
    return AlertDialog(
      title: const Text('配置 DeepL API Free'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('deepl-api-key'),
              controller: _keyController,
              focusNode: _keyFocusNode,
              autofocus: true,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                errorText: _error,
                suffixIcon: IconButton(
                  tooltip: _obscure ? '显示' : '隐藏',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Text(
              '密钥保存在系统安全存储中，请使用 DeepL API Free 密钥。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中' : '保存'),
        ),
      ],
    );
  }
}
