import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:re_editor/re_editor.dart';

import '../../core/settings/settings_store.dart';
import '../../core/desktop/desktop_text_selection.dart';
import '../../core/desktop/web_text_editor.dart';
import 'json_code_indicator.dart';
import 'json_document_controller.dart';
import 'json_editor_chrome.dart';
import 'json_find_panel.dart';
import 'json_fold_controller.dart';
import 'json_focus_restorer.dart';
import 'json_formatter_shortcuts.dart';
import 'json_highlight_theme.dart';
import 'json_transformer.dart';

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
  late final JsonFocusRestorer _focusRestorer;
  final _foldController = JsonFoldController();
  bool _syncing = false, _dragging = false;

  bool get _usesWebEditor =>
      (Platform.isMacOS || Platform.isWindows) &&
      !kIsWeb &&
      Platform.environment['FLUTTER_TEST'] != 'true';
  @override
  void initState() {
    super.initState();
    _editor = CodeLineEditingController.fromText(widget.controller.text);
    _findController = CodeFindController(_editor);
    _findController.addListener(_onFindChanged);
    _findController.findInputFocusNode.addListener(_onFindFieldFocusChanged);
    _findController.replaceInputFocusNode.addListener(_onFindFieldFocusChanged);
    _focusRestorer = JsonFocusRestorer(_findController, _editor);
    widget.controller.addListener(_syncFromDocument);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromDocument);
    _focusRestorer.dispose();
    _findController.removeListener(_onFindChanged);
    _findController.findInputFocusNode.removeListener(_onFindFieldFocusChanged);
    _findController.replaceInputFocusNode.removeListener(
      _onFindFieldFocusChanged,
    );
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

  void _onNativeEditorChanged(String text) {
    _syncing = true;
    _editor.text = text;
    _syncing = false;
    widget.controller.userEdit(text);
    if (mounted) setState(() {});
  }

  void _onNativeSelectionChanged(NativeTextSelection selection) {
    final next = _selectionFromOffset(
      selection.baseOffset,
      selection.extentOffset,
    );
    if (_editor.selection == next) return;
    _editor.selection = next;
    if (mounted) setState(() {});
  }

  NativeTextSelection _nativeSelection() {
    final selection = _editor.selection;
    return NativeTextSelection(
      baseOffset: _offsetFromPosition(
        selection.baseIndex,
        selection.baseOffset,
      ),
      extentOffset: _offsetFromPosition(
        selection.extentIndex,
        selection.extentOffset,
      ),
    );
  }

  int _offsetFromPosition(int lineIndex, int lineOffset) {
    final lines = _editor.codeLines;
    var offset = 0;
    final safeIndex = lineIndex.clamp(0, lines.length - 1);
    for (var index = 0; index < safeIndex; index++) {
      offset += lines[index].text.length + 1;
    }
    return offset + lineOffset.clamp(0, lines[safeIndex].text.length);
  }

  CodeLineSelection _selectionFromOffset(int baseOffset, int extentOffset) {
    return CodeLineSelection(
      baseIndex: _lineIndexFromOffset(baseOffset),
      baseOffset: _lineOffsetFromOffset(baseOffset),
      extentIndex: _lineIndexFromOffset(extentOffset),
      extentOffset: _lineOffsetFromOffset(extentOffset),
    );
  }

  int _lineIndexFromOffset(int offset) {
    final safeOffset = offset.clamp(0, _editor.text.length);
    var lineIndex = 0;
    for (var index = 0; index < safeOffset; index++) {
      if (_editor.text.codeUnitAt(index) == 10) lineIndex++;
    }
    return lineIndex;
  }

  int _lineOffsetFromOffset(int offset) {
    final safeOffset = offset.clamp(0, _editor.text.length);
    final lineStart = _editor.text.lastIndexOf('\n', safeOffset - 1);
    return safeOffset - lineStart - 1;
  }

  void _onFindChanged() {
    if (mounted) setState(() {});
  }

  void _onFindFieldFocusChanged() {
    if (_findController.findInputFocusNode.hasFocus ||
        _findController.replaceInputFocusNode.hasFocus) {
      DesktopWebTextEditor.suspendActiveEditorFocus();
    }
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

  Future<void> _compactAndCopy() async {
    final transformed = await widget.controller.transform(
      JsonTransformMode.compact,
      widget.settings.value.indentSize,
    );
    if (!transformed) return;
    await Clipboard.setData(ClipboardData(text: widget.controller.text));
    widget.controller.markSaved();
    if (mounted) _showMessage('已压缩并复制');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // The WebView editor owns its own native clipboard path. When the custom
    // Flutter find/replace panel is open, however, its TextFields still need
    // the guarded clipboard bridge (including QuickClipboard/iCopy).
    _focusRestorer.active =
        Visibility.of(context) &&
        (!_usesWebEditor || _findController.value != null);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shortcuts = buildJsonFormatterShortcuts(
      onFind: _findController.findMode,
      onReplace: _findController.replaceMode,
    );
    if (_findController.value != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.escape)] =
          _findController.close;
    }
    return CallbackShortcuts(
      bindings: shortcuts,
      child: _buildDropTarget(theme, isDark),
    );
  }

  Widget _buildDropTarget(ThemeData theme, bool isDark) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _handleDrop,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerLowest,
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
      onCompactAndCopy: _compactAndCopy,
      onFind: _findController.findMode,
      onCollapseAll: _usesWebEditor
          ? DesktopWebTextEditor.collapseActiveJson
          : _foldController.collapseAll,
      onExpandAll: _usesWebEditor
          ? DesktopWebTextEditor.expandActiveJson
          : _foldController.expandAll,
      showFoldControls: true,
    );
  }

  Widget _buildEditor(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: _dragging
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: _dragging ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withAlpha(isDark ? 52 : 16),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildCodeEditor(theme, isDark),
    );
  }

  Widget _buildCodeEditor(ThemeData theme, bool isDark) {
    if (_usesWebEditor) {
      return Stack(
        fit: StackFit.expand,
        children: [
          DesktopWebTextEditor(
            text: _editor.text,
            selection: _nativeSelection(),
            onChanged: _onNativeEditorChanged,
            onSelectionChanged: _onNativeSelectionChanged,
            onFind: _findController.findMode,
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            textColor: theme.colorScheme.onSurface,
            isDark: isDark,
            syntax: WebEditorSyntax.json,
          ),
          if (_findController.value != null)
            Positioned(
              top: 0,
              right: 0,
              child: JsonFindPanel(
                controller: _findController,
                readOnly: false,
                onPaste: _focusRestorer.pasteFocusedTarget,
              ),
            ),
        ],
      );
    }
    return CodeEditor(
      controller: _editor,
      findController: _findController,
      focusNode: _focusRestorer.editorFocusNode,
      onChanged: (_) => _onEditorChanged(),
      wordWrap: false,
      autofocus: true,
      shortcutsActivatorsBuilder: const JsonEditorShortcutsBuilder(),
      shortcutOverrideActions: buildJsonEditorActions(
        onPaste: _focusRestorer.pasteFocusedTarget,
      ),
      findBuilder: (context, controller, readOnly) => JsonFindPanel(
        controller: controller,
        readOnly: readOnly,
        onPaste: _focusRestorer.pasteFocusedTarget,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      style: buildJsonEditorStyle(
        isDark: isDark,
        cursorLineColor: theme.colorScheme.primary.withAlpha(20),
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
      ),
      indicatorBuilder: (context, editing, chunk, notifier) {
        _foldController.attach(editing, chunk);
        return JsonCodeIndicator(
          editingController: editing,
          chunkController: chunk,
          notifier: notifier,
        );
      },
      leadingDivider: ColoredBox(
        color: theme.colorScheme.outlineVariant.withAlpha(145),
        child: const SizedBox(width: 1),
      ),
    );
  }
}
