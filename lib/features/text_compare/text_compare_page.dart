import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/desktop/desktop_clipboard_focus_restorer.dart';
import '../../core/desktop/desktop_text_selection.dart';
import '../../core/desktop/web_text_editor.dart';
import 'text_compare_controller.dart';
import 'text_compare_indicator.dart';
import 'text_compare_models.dart';

class _TextCompareChunkAnalyzer implements CodeChunkAnalyzer {
  const _TextCompareChunkAnalyzer();

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

class _TextCompareFindMatch {
  const _TextCompareFindMatch(this.start, this.end);

  final int start;
  final int end;
}

class TextComparePage extends StatefulWidget {
  const TextComparePage({super.key, required this.controller});

  final TextCompareController controller;

  @override
  State<TextComparePage> createState() => _TextComparePageState();
}

class _TextComparePageState extends State<TextComparePage> {
  late final CodeLineEditingController _leftEditor;
  late final CodeLineEditingController _rightEditor;
  late final TextEditingController _leftWebController;
  late final TextEditingController _rightWebController;
  late final CodeScrollController _leftScrollController;
  late final CodeScrollController _rightScrollController;
  final _leftFocusNode = FocusNode();
  final _rightFocusNode = FocusNode();
  late final DesktopClipboardFocusRestorer _focusRestorer;
  bool _foldUnchanged = false;
  int _foldedLineCount = 0;
  bool _syncingScroll = false;
  bool _highlightRepaintScheduled = false;
  late final TextEditingController _findInputController;
  final _findFocusNode = FocusNode(debugLabel: 'text-compare-find');
  TextCompareSide _activeFindSide = TextCompareSide.left;
  List<_TextCompareFindMatch> _findMatches = const [];
  int _findMatchIndex = -1;
  bool _findVisible = false;

  bool get _usesWebEditor =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows) &&
      Platform.environment['FLUTTER_TEST'] != 'true';

  @override
  void initState() {
    super.initState();
    _leftEditor = _createEditor(TextCompareSide.left);
    _rightEditor = _createEditor(TextCompareSide.right);
    _leftWebController = TextEditingController(
      text: widget.controller.leftText,
    );
    _rightWebController = TextEditingController(
      text: widget.controller.rightText,
    );
    _leftScrollController = CodeScrollController();
    _rightScrollController = CodeScrollController();
    _findInputController = TextEditingController();
    _findInputController.addListener(_onFindQueryChanged);
    _leftScrollController.verticalScroller.addListener(_syncLeftScroll);
    _rightScrollController.verticalScroller.addListener(_syncRightScroll);
    _focusRestorer = DesktopClipboardFocusRestorer(
      targets: [
        CodeLineClipboardTarget(
          controller: _leftEditor,
          focusNode: _leftFocusNode,
          onChanged: widget.controller.updateLeft,
        ),
        CodeLineClipboardTarget(
          controller: _rightEditor,
          focusNode: _rightFocusNode,
          onChanged: widget.controller.updateRight,
        ),
      ],
    );
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
            codeLine: codeLine,
            text: codeLine.text,
            style: style,
          ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _focusRestorer.dispose();
    _leftScrollController.verticalScroller.removeListener(_syncLeftScroll);
    _rightScrollController.verticalScroller.removeListener(_syncRightScroll);
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    _leftScrollController.verticalScroller.dispose();
    _leftScrollController.horizontalScroller.dispose();
    _rightScrollController.verticalScroller.dispose();
    _rightScrollController.horizontalScroller.dispose();
    _findInputController.removeListener(_onFindQueryChanged);
    _findInputController.dispose();
    _findFocusNode.dispose();
    _leftFocusNode.removeListener(_handleFocusChange);
    _rightFocusNode.removeListener(_handleFocusChange);
    _leftEditor.dispose();
    _rightEditor.dispose();
    _leftWebController.dispose();
    _rightWebController.dispose();
    _leftFocusNode.dispose();
    _rightFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_leftFocusNode.hasFocus) {
      _setActiveFindSide(TextCompareSide.left);
    } else if (_rightFocusNode.hasFocus) {
      _setActiveFindSide(TextCompareSide.right);
    }
    if (mounted) setState(() {});
  }

  void _activateWebSide(TextCompareSide side) {
    _setActiveFindSide(side);
    _findFocusNode.unfocus();
    if (mounted) setState(() {});
  }

  void _setActiveFindSide(TextCompareSide side) {
    if (_activeFindSide == side) return;
    _activeFindSide = side;
    if (_findVisible) _refreshFindMatches(resetIndex: true);
  }

  String _findText(TextCompareSide side) {
    return side == TextCompareSide.left
        ? widget.controller.leftText
        : widget.controller.rightText;
  }

  TextEditingController _webControllerFor(TextCompareSide side) {
    return side == TextCompareSide.left
        ? _leftWebController
        : _rightWebController;
  }

  CodeLineEditingController _editorFor(TextCompareSide side) {
    return side == TextCompareSide.left ? _leftEditor : _rightEditor;
  }

  int _currentOffset(TextCompareSide side) {
    if (_usesWebEditor) {
      final controller = _webControllerFor(side);
      return controller.selection.extentOffset.clamp(0, controller.text.length);
    }
    final editor = _editorFor(side);
    final selection = editor.selection;
    final text = _findText(side);
    if (editor.codeLines.isEmpty) return 0;
    var offset = 0;
    final lineIndex = selection.extentIndex.clamp(
      0,
      editor.codeLines.length - 1,
    );
    for (var index = 0; index < lineIndex; index++) {
      offset += editor.codeLines[index].text.length + 1;
    }
    return (offset + selection.extentOffset).clamp(0, text.length);
  }

  void _openFind(TextCompareSide side) {
    _activeFindSide = side;
    _findVisible = true;
    _findFocusNode.requestFocus();
    _findInputController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _findInputController.text.length,
    );
    _refreshFindMatches(resetIndex: true);
    if (mounted) setState(() {});
  }

  void _closeFind() {
    _findFocusNode.unfocus();
    if (!_findVisible) return;
    setState(() {
      _findVisible = false;
      _findMatches = const [];
      _findMatchIndex = -1;
    });
  }

  void _onFindQueryChanged() {
    if (!_findVisible) return;
    _refreshFindMatches(resetIndex: true);
    if (mounted) setState(() {});
  }

  void _refreshFindMatches({required bool resetIndex}) {
    final query = _findInputController.text;
    final text = _findText(_activeFindSide);
    if (query.isEmpty) {
      _findMatches = const [];
      _findMatchIndex = -1;
      return;
    }
    final expression = RegExp(RegExp.escape(query), caseSensitive: false);
    _findMatches = [
      for (final match in expression.allMatches(text))
        _TextCompareFindMatch(match.start, match.end),
    ];
    if (_findMatches.isEmpty) {
      _findMatchIndex = -1;
      return;
    }
    if (resetIndex) {
      final offset = _currentOffset(_activeFindSide);
      _findMatchIndex = _findMatches.indexWhere(
        (match) => match.start >= offset,
      );
      if (_findMatchIndex < 0) _findMatchIndex = 0;
    } else {
      _findMatchIndex = _findMatchIndex.clamp(0, _findMatches.length - 1);
    }
    _revealCurrentFindMatch();
  }

  void _nextFindMatch() {
    if (_findMatches.isEmpty) return;
    _findMatchIndex = (_findMatchIndex + 1) % _findMatches.length;
    if (mounted) setState(() {});
    _revealCurrentFindMatch();
  }

  void _previousFindMatch() {
    if (_findMatches.isEmpty) return;
    _findMatchIndex =
        (_findMatchIndex - 1 + _findMatches.length) % _findMatches.length;
    if (mounted) setState(() {});
    _revealCurrentFindMatch();
  }

  void _revealCurrentFindMatch() {
    if (_findMatchIndex < 0 || _findMatchIndex >= _findMatches.length) return;
    final match = _findMatches[_findMatchIndex];
    final side = _activeFindSide;
    final text = _findText(side);
    if (_usesWebEditor) {
      final controller = _webControllerFor(side);
      controller.selection = TextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
      final selection = NativeTextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_findVisible ||
            _activeFindSide != side ||
            _findMatchIndex < 0 ||
            _findMatches[_findMatchIndex] != match) {
          return;
        }
        DesktopWebTextEditor.revealActiveSelection(selection);
      });
      return;
    }
    final editor = _editorFor(side);
    final start = _selectionFromOffset(text, match.start);
    final end = _selectionFromOffset(text, match.end);
    editor.selection = CodeLineSelection(
      baseIndex: start.baseIndex,
      baseOffset: start.baseOffset,
      extentIndex: end.baseIndex,
      extentOffset: end.baseOffset,
    );
    editor.makePositionCenterIfInvisible(editor.selection.start);
  }

  CodeLineSelection _selectionFromOffset(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    var lineIndex = 0;
    for (var index = 0; index < safeOffset; index++) {
      if (text.codeUnitAt(index) == 10) lineIndex++;
    }
    final lineStart = safeOffset == 0
        ? -1
        : text.lastIndexOf('\n', safeOffset - 1);
    final lineOffset = safeOffset - lineStart - 1;
    return CodeLineSelection.collapsed(index: lineIndex, offset: lineOffset);
  }

  void _syncLeftScroll() {
    _syncVerticalScroll(
      source: _leftScrollController.verticalScroller,
      target: _rightScrollController.verticalScroller,
    );
  }

  void _syncRightScroll() {
    _syncVerticalScroll(
      source: _rightScrollController.verticalScroller,
      target: _leftScrollController.verticalScroller,
    );
  }

  void _syncVerticalScroll({
    required ScrollController source,
    required ScrollController target,
  }) {
    if (_syncingScroll || !source.hasClients || !target.hasClients) return;
    final nextOffset = source.offset
        .clamp(0.0, target.position.maxScrollExtent)
        .toDouble();
    if ((target.offset - nextOffset).abs() < 0.5) return;
    _syncingScroll = true;
    target.jumpTo(nextOffset);
    _syncingScroll = false;
  }

  void _syncFromController() {
    var textChanged = false;
    if (_leftEditor.text != widget.controller.leftText) {
      _leftEditor.text = widget.controller.leftText;
      textChanged = true;
    }
    if (_rightEditor.text != widget.controller.rightText) {
      _rightEditor.text = widget.controller.rightText;
      textChanged = true;
    }
    if (_leftWebController.text != widget.controller.leftText) {
      _leftWebController.value = TextEditingValue(
        text: widget.controller.leftText,
        selection: TextSelection.collapsed(
          offset: widget.controller.leftText.length,
        ),
      );
      textChanged = true;
    }
    if (_rightWebController.text != widget.controller.rightText) {
      _rightWebController.value = TextEditingValue(
        text: widget.controller.rightText,
        selection: TextSelection.collapsed(
          offset: widget.controller.rightText.length,
        ),
      );
      textChanged = true;
    }
    if (_findVisible && textChanged) {
      _refreshFindMatches(resetIndex: true);
    }
    // Diff spans are derived from the controller result rather than editor
    // text. `setState` below lets the existing editors rebuild their spans;
    // calling re_editor's forceRepaint here is unsafe because this listener
    // can run during a scroll/layout update triggered by a paste.
    if (mounted) {
      setState(() {});
      _scheduleHighlightRepaint();
      _scheduleFoldingUpdate();
    }
  }

  NativeTextSelection _webSelection(TextEditingController controller) {
    final selection = controller.selection;
    return NativeTextSelection(
      baseOffset: selection.baseOffset.clamp(0, controller.text.length),
      extentOffset: selection.extentOffset.clamp(0, controller.text.length),
    );
  }

  void _webSelectionChanged(
    TextEditingController controller,
    NativeTextSelection selection,
  ) {
    final length = controller.text.length;
    controller.selection = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, length),
      extentOffset: selection.extentOffset.clamp(0, length),
    );
  }

  void _webChanged(TextCompareSide side, String text) {
    final controller = side == TextCompareSide.left
        ? _leftWebController
        : _rightWebController;
    final selection = controller.selection;
    controller.value = TextEditingValue(
      text: text,
      selection: selection.copyWith(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
      ),
    );
    if (side == TextCompareSide.left) {
      widget.controller.updateLeft(text);
    } else {
      widget.controller.updateRight(text);
    }
  }

  Future<void> _pasteWeb(TextCompareSide side) async {
    final controller = side == TextCompareSide.left
        ? _leftWebController
        : _rightWebController;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted == null) return;
    final current = controller.text;
    final selection = controller.selection;
    final start = selection.start.clamp(0, current.length);
    final end = selection.end.clamp(start, current.length);
    final next = current.replaceRange(start, end, pasted);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + pasted.length),
    );
    if (side == TextCompareSide.left) {
      widget.controller.updateLeft(next);
    } else {
      widget.controller.updateRight(next);
    }
  }

  List<DesktopTextHighlight> _webHighlights(
    BuildContext context,
    TextCompareSide side,
  ) {
    final result = widget.controller.result;
    if (result == null) return const [];
    final lines = side == TextCompareSide.left
        ? result.leftLines
        : result.rightLines;
    final text = side == TextCompareSide.left
        ? widget.controller.leftText
        : widget.controller.rightText;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highlights = <DesktopTextHighlight>[];
    var offset = 0;
    for (final line in lines) {
      final lineEnd = offset + _lineLengthAt(text, offset);
      if (line.status != TextDiffLineStatus.unchanged && lineEnd > offset) {
        final color = switch (line.status) {
          TextDiffLineStatus.added =>
            dark ? const Color(0xFF183B2C) : const Color(0xFFE0F2E7),
          TextDiffLineStatus.removed =>
            dark ? const Color(0xFF432220) : const Color(0xFFFBE3E0),
          TextDiffLineStatus.modified =>
            dark ? const Color(0xFF493514) : const Color(0xFFFFEBC7),
          TextDiffLineStatus.unchanged => Colors.transparent,
        };
        highlights.add(
          DesktopTextHighlight(
            start: offset,
            end: lineEnd,
            backgroundColor: color,
          ),
        );
      }
      offset = lineEnd;
      if (offset < text.length && text.codeUnitAt(offset) == 10) offset++;
    }
    return highlights;
  }

  int _lineLengthAt(String text, int offset) {
    final end = text.indexOf('\n', offset);
    return (end < 0 ? text.length : end) - offset;
  }

  void _scheduleHighlightRepaint() {
    if (_highlightRepaintScheduled) return;
    _highlightRepaintScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _highlightRepaintScheduled = false;
      if (!mounted) return;
      // re_editor caches the paragraphs generated by spanBuilder. The diff
      // result changes independently of the editor value, so invalidate that
      // cache after the frame instead of waiting for a focus or cursor event
      // to trigger the first repaint.
      _leftEditor.forceRepaint();
      _rightEditor.forceRepaint();
    });
  }

  void _setFoldUnchanged(bool value) {
    if (_foldUnchanged == value) return;
    setState(() => _foldUnchanged = value);
    _scheduleFoldingUpdate();
  }

  void _scheduleFoldingUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateFolding();
    });
  }

  void _updateFolding() {
    _expandAllChunks(_leftEditor);
    _expandAllChunks(_rightEditor);
    if (!_foldUnchanged) {
      _setFoldedLineCount(0);
      return;
    }
    final result = widget.controller.result;
    if (result == null) {
      _setFoldedLineCount(0);
      return;
    }
    final leftCount = _collapseUnchangedRuns(_leftEditor, result.leftLines);
    final rightCount = _collapseUnchangedRuns(_rightEditor, result.rightLines);
    _setFoldedLineCount(leftCount > rightCount ? leftCount : rightCount);
  }

  void _setFoldedLineCount(int count) {
    if (_foldedLineCount == count || !mounted) return;
    setState(() => _foldedLineCount = count);
  }

  void _expandAllChunks(CodeLineEditingController editor) {
    for (var index = editor.codeLines.length - 1; index >= 0; index--) {
      if (editor.codeLines[index].chunkParent) {
        editor.expandChunk(index);
      }
    }
  }

  int _collapseUnchangedRuns(
    CodeLineEditingController editor,
    List<TextDiffLine> lines,
  ) {
    const contextLines = 2;
    final ranges = <({int start, int end})>[];
    var runStart = -1;
    for (var index = 0; index <= lines.length; index++) {
      final unchanged =
          index < lines.length &&
          lines[index].status == TextDiffLineStatus.unchanged;
      if (unchanged && runStart < 0) {
        runStart = index;
      } else if (!unchanged && runStart >= 0) {
        final runEnd = index - 1;
        final start = runStart + contextLines - 1;
        // collapseChunk keeps the line at `end` visible, so this is the first
        // of the trailing context lines rather than the last hidden line.
        final end = runEnd - contextLines + 1;
        if (end > start + 1) {
          ranges.add((start: start, end: end));
        }
        runStart = -1;
      }
    }
    var foldedLineCount = 0;
    for (final range in ranges.reversed) {
      editor.collapseChunk(range.start, range.end);
      foldedLineCount += range.end - range.start - 1;
    }
    return foldedLineCount;
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
    required CodeLine codeLine,
    required String text,
    required TextStyle style,
  }) {
    if (codeLine.chunkParent) {
      final hiddenLines = codeLine.chunks.length;
      final collapsedStyle = style.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        fontWeight: FontWeight.w600,
      );
      return TextSpan(text: '  $hiddenLines 行未更改行已折叠  ', style: collapsedStyle);
    }
    final result = widget.controller.result;
    final lines = side == TextCompareSide.left
        ? result?.leftLines
        : result?.rightLines;
    final editor = side == TextCompareSide.left ? _leftEditor : _rightEditor;
    final originalIndex = editor.codeLines.index2lineIndex(index);
    if (lines == null || originalIndex < 0 || originalIndex >= lines.length) {
      return TextSpan(text: text, style: style);
    }
    final line = lines[originalIndex];
    final colors = _diffColors(context, side, line.status);
    final lineStyle = style.copyWith(
      backgroundColor: colors.line,
      fontWeight: line.status == TextDiffLineStatus.unchanged
          ? style.fontWeight
          : FontWeight.w600,
    );
    if (line.ranges.isEmpty) {
      return TextSpan(text: text, style: lineStyle);
    }
    final children = <TextSpan>[];
    var offset = 0;
    for (final range in line.ranges) {
      if (range.start > offset) {
        children.add(
          TextSpan(text: text.substring(offset, range.start), style: lineStyle),
        );
      }
      children.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: lineStyle.copyWith(
            backgroundColor: colors.character,
            color: colors.characterText,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      offset = range.end;
    }
    if (offset < text.length) {
      children.add(TextSpan(text: text.substring(offset), style: lineStyle));
    }
    return TextSpan(style: lineStyle, children: children);
  }

  ({Color line, Color character, Color characterText}) _diffColors(
    BuildContext context,
    TextCompareSide side,
    TextDiffLineStatus status,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = switch (status) {
      TextDiffLineStatus.added =>
        dark ? const Color(0xFF183B2C) : const Color(0xFFE0F2E7),
      TextDiffLineStatus.removed =>
        dark ? const Color(0xFF432220) : const Color(0xFFFBE3E0),
      TextDiffLineStatus.modified =>
        dark ? const Color(0xFF493514) : const Color(0xFFFFEBC7),
      TextDiffLineStatus.unchanged => Colors.transparent,
    };
    final character = switch (status) {
      TextDiffLineStatus.added =>
        dark ? const Color(0xFF246B49) : const Color(0xFFB9E7CA),
      TextDiffLineStatus.removed =>
        dark ? const Color(0xFF8B3D3A) : const Color(0xFFFFC7C2),
      TextDiffLineStatus.modified =>
        side == TextCompareSide.left
            ? (dark ? const Color(0xFF8B3D3A) : const Color(0xFFFFC7C2))
            : (dark ? const Color(0xFF246B49) : const Color(0xFFB9E7CA)),
      TextDiffLineStatus.unchanged => Colors.transparent,
    };
    final characterText = switch (status) {
      TextDiffLineStatus.added =>
        dark ? const Color(0xFFE8FFF0) : const Color(0xFF0B4A2D),
      TextDiffLineStatus.removed =>
        dark ? const Color(0xFFFFECEA) : const Color(0xFF711C17),
      TextDiffLineStatus.modified =>
        side == TextCompareSide.left
            ? (dark ? const Color(0xFFFFECEA) : const Color(0xFF711C17))
            : (dark ? const Color(0xFFE8FFF0) : const Color(0xFF0B4A2D)),
      TextDiffLineStatus.unchanged => Theme.of(context).colorScheme.onSurface,
    };
    return (line: line, character: character, characterText: characterText);
  }

  @override
  Widget build(BuildContext context) {
    _focusRestorer.active = Visibility.of(context) && !_usesWebEditor;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            widget.controller.compare,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            widget.controller.compare,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _openFind(_activeFindSide),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _openFind(_activeFindSide),
        if (_findVisible)
          const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
        if (_findVisible)
          const SingleActivator(LogicalKeyboardKey.arrowDown): _nextFindMatch,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  _CompareToolbar(
                    controller: widget.controller,
                    foldUnchanged: _foldUnchanged,
                    foldedLineCount: _foldedLineCount,
                    showFoldUnchanged: !_usesWebEditor,
                    onFoldUnchangedChanged: _setFoldUnchanged,
                    onOpenLeft: () => _openFile(TextCompareSide.left),
                    onOpenRight: () => _openFile(TextCompareSide.right),
                    onCopySummary: _copySummary,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: _TextPane(
                              side: TextCompareSide.left,
                              controller: widget.controller,
                              editor: _leftEditor,
                              scrollController: _leftScrollController,
                              focusNode: _leftFocusNode,
                              emphasized: _leftFocusNode.hasFocus,
                              onPaste: () => _usesWebEditor
                                  ? _pasteWeb(TextCompareSide.left)
                                  : _focusRestorer.pasteFocusedTarget(),
                              onFind: () => _openFind(TextCompareSide.left),
                              onEditorPointerDown: () =>
                                  _activateWebSide(TextCompareSide.left),
                              useWebEditor: _usesWebEditor,
                              webController: _leftWebController,
                              webSelection: _webSelection(_leftWebController),
                              webHighlights: _webHighlights(
                                context,
                                TextCompareSide.left,
                              ),
                              onWebSelectionChanged: (value) =>
                                  _webSelectionChanged(
                                    _leftWebController,
                                    value,
                                  ),
                              onWebChanged: (value) =>
                                  _webChanged(TextCompareSide.left, value),
                              onChanged: (_) => widget.controller.updateLeft(
                                _leftEditor.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _TextPane(
                              side: TextCompareSide.right,
                              controller: widget.controller,
                              editor: _rightEditor,
                              scrollController: _rightScrollController,
                              focusNode: _rightFocusNode,
                              emphasized: _rightFocusNode.hasFocus,
                              onPaste: () => _usesWebEditor
                                  ? _pasteWeb(TextCompareSide.right)
                                  : _focusRestorer.pasteFocusedTarget(),
                              onFind: () => _openFind(TextCompareSide.right),
                              onEditorPointerDown: () =>
                                  _activateWebSide(TextCompareSide.right),
                              useWebEditor: _usesWebEditor,
                              webController: _rightWebController,
                              webSelection: _webSelection(_rightWebController),
                              webHighlights: _webHighlights(
                                context,
                                TextCompareSide.right,
                              ),
                              onWebSelectionChanged: (value) =>
                                  _webSelectionChanged(
                                    _rightWebController,
                                    value,
                                  ),
                              onWebChanged: (value) =>
                                  _webChanged(TextCompareSide.right, value),
                              onChanged: (_) => widget.controller.updateRight(
                                _rightEditor.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _CompareStatusBar(controller: widget.controller),
                ],
              ),
              if (_findVisible)
                Positioned(
                  top: 66,
                  right: 24,
                  child: _TextCompareFindPanel(
                    controller: _findInputController,
                    focusNode: _findFocusNode,
                    matchIndex: _findMatchIndex,
                    matchCount: _findMatches.length,
                    onPrevious: _previousFindMatch,
                    onNext: _nextFindMatch,
                    onClose: _closeFind,
                  ),
                ),
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
    required this.foldUnchanged,
    required this.foldedLineCount,
    required this.showFoldUnchanged,
    required this.onFoldUnchangedChanged,
    required this.onOpenLeft,
    required this.onOpenRight,
    required this.onCopySummary,
  });

  final TextCompareController controller;
  final bool foldUnchanged;
  final int foldedLineCount;
  final bool showFoldUnchanged;
  final ValueChanged<bool> onFoldUnchangedChanged;
  final VoidCallback onOpenLeft;
  final VoidCallback onOpenRight;
  final VoidCallback onCopySummary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withAlpha(10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '文本比对',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(width: 4),
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
            if (showFoldUnchanged)
              _OptionToggle(
                label: '折叠未更改行',
                value: foldUnchanged,
                onChanged: onFoldUnchangedChanged,
              ),
            if (showFoldUnchanged && foldUnchanged)
              Text(
                foldedLineCount > 0 ? '已折叠 $foldedLineCount 行' : '无可折叠行',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const _DiffLegend(),
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

class _DiffLegend extends StatelessWidget {
  const _DiffLegend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendItem(color: scheme.error, label: '删除'),
        const SizedBox(width: 7),
        _LegendItem(color: const Color(0xFFD18A16), label: '修改'),
        const SizedBox(width: 7),
        _LegendItem(color: const Color(0xFF2E9B63), label: '新增'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TextCompareFindPanel extends StatelessWidget {
  const _TextCompareFindPanel({
    required this.controller,
    required this.focusNode,
    required this.matchIndex,
    required this.matchCount,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int matchIndex;
  final int matchCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resultText = matchIndex < 0 || matchCount == 0
        ? '0/0'
        : '${matchIndex + 1}/$matchCount';
    return Container(
      width: 430,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withAlpha(28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): onNext,
                const SingleActivator(LogicalKeyboardKey.arrowDown): onNext,
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              },
              child: TextField(
                key: const ValueKey('text-compare-find-input'),
                controller: controller,
                focusNode: focusNode,
                maxLines: 1,
                onEditingComplete: () {},
                onSubmitted: (_) => onNext(),
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: '查找',
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainer,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                ),
              ),
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
          IconButton(
            tooltip: '上一个',
            onPressed: matchCount == 0 ? null : onPrevious,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: '下一个',
            onPressed: matchCount == 0 ? null : onNext,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          IconButton(
            tooltip: '关闭查找',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _TextPane extends StatelessWidget {
  const _TextPane({
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
    required this.webController,
    required this.webSelection,
    required this.webHighlights,
    required this.onWebSelectionChanged,
    required this.onWebChanged,
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
  final TextEditingController webController;
  final NativeTextSelection webSelection;
  final List<DesktopTextHighlight> webHighlights;
  final ValueChanged<NativeTextSelection> onWebSelectionChanged;
  final ValueChanged<String> onWebChanged;

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
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          children: [
            Container(
              height: 52,
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
              child: useWebEditor
                  ? DesktopWebTextEditor(
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
                      debugLabel: isLeft
                          ? 'text-compare-left'
                          : 'text-compare-right',
                      autofocus: isLeft,
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
                      chunkAnalyzer: const _TextCompareChunkAnalyzer(),
                      onChanged: onChanged,
                      hint: isLeft ? '输入或粘贴旧文本' : '输入或粘贴新文本',
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                      style: CodeEditorStyle(
                        fontSize: 14,
                        fontHeight: 1.6,
                        fontFamily: 'Menlo',
                        fontFamilyFallback: const ['Consolas', 'monospace'],
                        backgroundColor: scheme.surfaceContainerLowest,
                        cursorColor: scheme.primary,
                        cursorLineColor: scheme.primary.withAlpha(24),
                      ),
                      indicatorBuilder:
                          (
                            context,
                            editingController,
                            chunkController,
                            notifier,
                          ) {
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
              height: 36,
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
