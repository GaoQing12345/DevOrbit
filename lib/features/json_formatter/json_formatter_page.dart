import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../core/settings/settings_store.dart';
import 'json_code_indicator.dart';
import 'json_document_controller.dart';
import 'json_editor_chrome.dart';
import 'json_find_panel.dart';

class JsonFormatterPage extends StatefulWidget {
  const JsonFormatterPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final JsonDocumentController controller;
  final SettingsStore settings;

  @override
  State<JsonFormatterPage> createState() => _JsonFormatterPageState();
}

class _JsonFormatterPageState extends State<JsonFormatterPage> {
  late final CodeLineEditingController _editor;
  late final CodeFindController _findController;
  bool _syncing = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _editor = CodeLineEditingController.fromText(widget.controller.text);
    _findController = CodeFindController(_editor);
    widget.controller.addListener(_syncFromDocument);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromDocument);
    _findController.dispose();
    _editor.dispose();
    super.dispose();
  }

  void _syncFromDocument() {
    if (_editor.text == widget.controller.text) {
      if (mounted) setState(() {});
      return;
    }
    _syncing = true;
    _editor.text = widget.controller.text;
    _syncing = false;
    if (mounted) setState(() {});
  }

  void _onEditorChanged() {
    if (!_syncing) widget.controller.userEdit(_editor.text);
  }

  Future<bool> _confirmReplace() async {
    if (!widget.controller.isDirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('替换当前内容？'),
            content: const Text('当前内容尚未保存或复制，替换后无法恢复。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('替换'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openFile() async {
    if (!await _confirmReplace()) return;
    const group = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    await _loadFile(file);
  }

  Future<void> _loadFile(XFile file) async {
    try {
      final text = await file.readAsString();
      await widget.controller.loadText(text, filePath: file.path);
    } catch (error) {
      if (mounted) _showMessage('无法读取文件：$error');
    }
  }

  Future<void> _saveFile() async {
    if (widget.controller.status == JsonDocumentStatus.invalid) {
      final shouldSave = await _confirmInvalidSave();
      if (!shouldSave) return;
    }
    var targetPath = widget.controller.filePath;
    if (targetPath == null) {
      final location = await getSaveLocation(
        suggestedName: 'data.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      targetPath = location?.path;
    }
    if (targetPath == null) return;
    final data = Uint8List.fromList(utf8.encode(widget.controller.text));
    final file = XFile.fromData(
      data,
      name: path.basename(targetPath),
      mimeType: 'application/json',
    );
    await file.saveTo(targetPath);
    widget.controller.markSaved(filePath: targetPath);
    if (mounted) _showMessage('已保存');
  }

  Future<bool> _confirmInvalidSave() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('JSON 尚未通过校验'),
            content: const Text('仍要保存当前内容吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('仍然保存'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.controller.text));
    widget.controller.markSaved();
    if (mounted) _showMessage('已复制到剪贴板');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return CallbackShortcuts(
      bindings: {_findShortcut(): _findController.findMode},
      child: _buildDropTarget(theme, isDark),
    );
  }

  ShortcutActivator _findShortcut() {
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    return SingleActivator(
      LogicalKeyboardKey.keyF,
      meta: isMacOS,
      control: !isMacOS,
    );
  }

  Widget _buildDropTarget(ThemeData theme, bool isDark) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _handleDrop,
      child: ColoredBox(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            _buildToolbar(),
            Expanded(child: _buildEditor(theme, isDark)),
            JsonEditorStatusBar(controller: widget.controller),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (details.files.isEmpty || !await _confirmReplace()) return;
    final file = details.files.first;
    if (!file.name.toLowerCase().endsWith('.json')) {
      _showMessage('仅支持 .json 文件');
      return;
    }
    await _loadFile(file);
  }

  Widget _buildToolbar() {
    return JsonEditorToolbar(
      controller: widget.controller,
      settings: widget.settings,
      onOpen: _openFile,
      onSave: _saveFile,
      onCopy: _copy,
      onFind: _findController.findMode,
    );
  }

  Widget _buildEditor(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        border: Border.all(
          color: _dragging
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: _dragging ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildCodeEditor(theme, isDark),
    );
  }

  Widget _buildCodeEditor(ThemeData theme, bool isDark) {
    return CodeEditor(
      controller: _editor,
      findController: _findController,
      onChanged: (_) => _onEditorChanged(),
      wordWrap: false,
      autofocus: true,
      findBuilder: (context, controller, readOnly) =>
          JsonFindPanel(controller: controller, readOnly: readOnly),
      style: CodeEditorStyle(
        fontSize: 14,
        fontFamily: 'Menlo',
        fontFamilyFallback: const ['Consolas', 'monospace'],
        backgroundColor: isDark
            ? const Color(0xFF15191E)
            : const Color(0xFFF8FAFA),
        cursorLineColor: theme.colorScheme.primary.withAlpha(30),
        codeTheme: CodeHighlightTheme(
          languages: {'json': CodeHighlightThemeMode(mode: langJson)},
          theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
        ),
      ),
      indicatorBuilder: (context, editing, chunk, notifier) =>
          JsonCodeIndicator(
            editingController: editing,
            chunkController: chunk,
            notifier: notifier,
          ),
      leadingDivider: ColoredBox(
        color: theme.colorScheme.outlineVariant.withAlpha(145),
        child: const SizedBox(width: 1),
      ),
    );
  }
}
