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
import 'text_compare_find_panel.dart';
import 'text_compare_models.dart';
import 'text_compare_pane.dart';
import 'text_compare_status_bar.dart';
import 'text_compare_toolbar.dart';

class _TextCompareFindMatch {
  const _TextCompareFindMatch(this.side, this.start, this.end);

  final TextCompareSide side;
  final int start;
  final int end;
}

/// Vertical padding both editors are built with. re_editor counts it inside the
/// scrollable content, which is what lets the line height be derived from the
/// scroll metrics alone.
const double _editorPaddingTop = 12;
const double _editorPaddingBottom = 18;

/// Translates between a pixel scroll offset and a line position for one pane.
///
/// [lineAt] keeps the fraction of a line, so two panes showing the same content
/// land on exactly the same pixel and an aligned scroll does not drift.
class _PaneScrollMetrics {
  const _PaneScrollMetrics({
    required this.lineHeight,
    required this.topPadding,
  });

  final double lineHeight;
  final double topPadding;

  double lineAt(double offset) => (offset - topPadding) / lineHeight;

  double offsetOf(double line) => line * lineHeight + topPadding;
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
  final _leftWebEditorController = DesktopWebTextEditorController();
  final _rightWebEditorController = DesktopWebTextEditorController();
  late final CodeScrollController _leftScrollController;
  late final CodeScrollController _rightScrollController;
  final _leftFocusNode = FocusNode();
  final _rightFocusNode = FocusNode();
  final _pageFocusNode = FocusNode(debugLabel: 'text-compare-page');
  late final DesktopClipboardFocusRestorer _focusRestorer;
  bool _foldUnchanged = false;
  int _foldedLineCount = 0;
  int _diffIndex = -1;
  TextDiffResult? _syncedResult;
  final _revealedLeftLines = <int>{};
  final _revealedRightLines = <int>{};
  bool _syncingScroll = false;
  bool _syncScrollEnabled = true;
  bool _highlightRepaintScheduled = false;
  late final TextEditingController _findInputController;
  final _findFocusNode = FocusNode(debugLabel: 'text-compare-find');
  TextCompareSide _activeEditorSide = TextCompareSide.left;
  TextCompareSide _findStartSide = TextCompareSide.left;
  List<_TextCompareFindMatch> _findMatches = const [];
  int _findMatchIndex = -1;
  bool _findVisible = false;
  bool _findSessionActive = false;

  bool get _usesWebEditor =>
      !kIsWeb &&
      Platform.isMacOS &&
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
        TextEditingClipboardTarget(
          controller: _findInputController,
          focusNode: _findFocusNode,
          available: () => _findVisible,
        ),
      ],
    );
    widget.controller.addListener(_syncFromController);
    _leftFocusNode.addListener(_handleFocusChange);
    _rightFocusNode.addListener(_handleFocusChange);
    _findFocusNode.addListener(_onFindFocusChanged);
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
    _findFocusNode.removeListener(_onFindFocusChanged);
    _findFocusNode.dispose();
    _leftFocusNode.removeListener(_handleFocusChange);
    _rightFocusNode.removeListener(_handleFocusChange);
    _leftEditor.dispose();
    _rightEditor.dispose();
    _leftWebController.dispose();
    _rightWebController.dispose();
    _leftFocusNode.dispose();
    _rightFocusNode.dispose();
    _pageFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_leftFocusNode.hasFocus) {
      _setActiveEditorSide(TextCompareSide.left);
    } else if (_rightFocusNode.hasFocus) {
      _setActiveEditorSide(TextCompareSide.right);
    }
    if (mounted) setState(() {});
  }

  void _activateWebSide(TextCompareSide side) {
    _findSessionActive = false;
    _focusRestorer.clearActiveTarget();
    _findFocusNode.unfocus();
    _setActiveEditorSide(side);
    _pageFocusNode.requestFocus();
    if (mounted) setState(() {});
  }

  void _setActiveEditorSide(TextCompareSide side) {
    if (_activeEditorSide == side) return;
    _activeEditorSide = side;
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

  DesktopWebTextEditorController _webEditorControllerFor(TextCompareSide side) {
    return side == TextCompareSide.left
        ? _leftWebEditorController
        : _rightWebEditorController;
  }

  FocusNode _editorFocusNodeFor(TextCompareSide side) {
    return side == TextCompareSide.left ? _leftFocusNode : _rightFocusNode;
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
    _activeEditorSide = side;
    _findStartSide = side;
    _findVisible = true;
    _findSessionActive = true;
    _findInputController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _findInputController.text.length,
    );
    _refreshFindMatches(resetIndex: true);
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _findVisible) _findFocusNode.requestFocus();
      });
    }
  }

  void _closeFind() {
    final restoreSide =
        _findMatchIndex >= 0 && _findMatchIndex < _findMatches.length
        ? _findMatches[_findMatchIndex].side
        : _activeEditorSide;
    _findSessionActive = false;
    _focusRestorer.clearActiveTarget();
    _findFocusNode.unfocus();
    if (!_findVisible) return;
    setState(() {
      _findVisible = false;
      _findMatches = const [];
      _findMatchIndex = -1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_usesWebEditor) {
        _webEditorControllerFor(restoreSide).restoreFocus();
      } else {
        _editorFocusNodeFor(restoreSide).requestFocus();
      }
    });
  }

  void _onFindFocusChanged() {
    if (_findFocusNode.hasFocus) {
      _findSessionActive = true;
      DesktopWebTextEditor.suspendActiveEditorFocus();
    } else if (_findSessionActive &&
        _focusRestorer.shouldReleaseTargetOnFocusExit) {
      _findSessionActive = false;
      _focusRestorer.clearActiveTarget();
    }
    if (mounted) setState(() {});
  }

  void _onFindQueryChanged() {
    if (!_findVisible) return;
    _refreshFindMatches(resetIndex: true);
    if (mounted) setState(() {});
  }

  void _refreshFindMatches({required bool resetIndex}) {
    final query = _findInputController.text;
    if (query.isEmpty) {
      _findMatches = const [];
      _findMatchIndex = -1;
      return;
    }
    final expression = RegExp(RegExp.escape(query), caseSensitive: false);
    final sides = _findStartSide == TextCompareSide.left
        ? const [TextCompareSide.left, TextCompareSide.right]
        : const [TextCompareSide.right, TextCompareSide.left];
    _findMatches = [
      for (final side in sides)
        for (final match in expression.allMatches(_findText(side)))
          _TextCompareFindMatch(side, match.start, match.end),
    ];
    if (_findMatches.isEmpty) {
      _findMatchIndex = -1;
      return;
    }
    if (resetIndex) {
      final offset = _currentOffset(_findStartSide);
      var index = _findMatches.indexWhere(
        (match) => match.side == _findStartSide && match.start >= offset,
      );
      if (index < 0) index = 0;
      _findMatchIndex = index;
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
    final side = match.side;
    _activeEditorSide = side;
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
            _findMatchIndex < 0 ||
            _findMatches[_findMatchIndex] != match) {
          return;
        }
        _webEditorControllerFor(side).revealSelection(selection);
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

  void _goToNextDiff() => _selectDiff(_diffIndex + 1);

  void _goToPreviousDiff() => _selectDiff(_diffIndex - 1);

  /// Moves the viewport to the given change block, wrapping around at both
  /// ends like the other comparers do. Only the scroll position moves; the
  /// caret and the paste ownership stay where the user left them.
  void _selectDiff(int index) {
    final hunks = widget.controller.hunks;
    if (hunks.isEmpty) return;
    final next = index < 0
        ? hunks.length - 1
        : (index >= hunks.length ? 0 : index);
    final result = widget.controller.result;
    if (result == null) return;
    if (mounted) setState(() => _diffIndex = next);
    final hunk = hunks[next];
    if (_foldUnchanged) {
      if (result.leftLines.isNotEmpty) {
        _revealedLeftLines.add(
          _clampLine(hunk.leftIndex, result.leftLines.length),
        );
      }
      if (result.rightLines.isNotEmpty) {
        _revealedRightLines.add(
          _clampLine(hunk.rightIndex, result.rightLines.length),
        );
      }
    }
    _revealLine(TextCompareSide.left, hunk.leftIndex);
    _revealLine(TextCompareSide.right, hunk.rightIndex);
  }

  int _clampLine(int index, int lineCount) =>
      index < 0 ? 0 : (index >= lineCount ? lineCount - 1 : index);

  void _revealLine(TextCompareSide side, int lineIndex) {
    final text = _findText(side);
    if (_usesWebEditor) {
      if (text.isEmpty) return;
      final offset = _lineStartOffset(text, lineIndex).clamp(0, text.length);
      final controller = _webControllerFor(side);
      controller.selection = TextSelection.collapsed(offset: offset);
      final selection = NativeTextSelection(
        baseOffset: offset,
        extentOffset: offset,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _webEditorControllerFor(side).revealSelection(selection);
      });
      return;
    }
    final editor = _editorFor(side);
    if (editor.codeLines.isEmpty || editor.lineCount == 0) return;
    final target = _clampLine(lineIndex, editor.lineCount);
    if (_foldUnchanged) _expandChunkContaining(editor, target);
    final visible = editor.codeLines.lineIndex2Index(target);
    if (visible.index < 0 || visible.index >= editor.codeLines.length) return;
    editor.makePositionCenterIfInvisible(
      CodeLinePosition(index: visible.index, offset: 0),
    );
  }

  /// `lineIndex2Index` reports a positive chunk offset when the wanted line is
  /// hidden inside a folded run, which is the signal to unfold that run.
  void _expandChunkContaining(CodeLineEditingController editor, int lineIndex) {
    final location = editor.codeLines.lineIndex2Index(lineIndex);
    if (location.index < 0 || location.chunkIndex < 0) return;
    if (location.index >= editor.codeLines.length) return;
    if (!editor.codeLines[location.index].chunkParent) return;
    editor.expandChunk(location.index);
  }

  int _lineStartOffset(String text, int lineIndex) {
    if (lineIndex <= 0) return 0;
    var offset = 0;
    for (var line = 0; line < lineIndex; line++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) return text.length;
      offset = next + 1;
    }
    return offset;
  }

  void _syncLeftScroll() => _syncVerticalScroll(TextCompareSide.left);

  void _syncRightScroll() => _syncVerticalScroll(TextCompareSide.right);

  /// Keeps the two panes on the same content while either one scrolls.
  ///
  /// Both editors share one typography, so the line height is derived from the
  /// pane's own scroll metrics instead of being hard-coded. The offset the
  /// source sits at is turned into a line index, that line is paired with its
  /// counterpart through the diff, and only then turned back into an offset —
  /// so an insertion on one side no longer pushes the two panes apart.
  void _syncVerticalScroll(TextCompareSide side) {
    if (!_syncScrollEnabled || _syncingScroll) return;
    final source = _scrollControllerFor(side).verticalScroller;
    final target = _scrollControllerFor(side.opposite).verticalScroller;
    if (!source.hasClients || !target.hasClients) return;
    final sourceLines = _editorFor(side).codeLines.length;
    final targetLines = _editorFor(side.opposite).codeLines.length;
    if (sourceLines <= 0 || targetLines <= 0) return;
    final sourceMetrics = _paneMetrics(source, sourceLines);
    final targetMetrics = _paneMetrics(target, targetLines) ?? sourceMetrics;
    if (sourceMetrics == null || targetMetrics == null) return;

    final sourceLine = sourceMetrics.lineAt(source.offset);
    final index = sourceLine.floor();
    final map = side == TextCompareSide.left
        ? widget.controller.result?.leftToRight
        : widget.controller.result?.rightToLeft;
    // Without a pairing the panes have nothing in common to align to, so the
    // plain offset mirror is the best that can be done.
    final paired = (map == null || index < 0 || index >= map.length)
        ? index
        : map[index];
    if (paired < 0) return;
    final targetLine = paired + (sourceLine - index);
    final nextOffset = targetMetrics
        .offsetOf(targetLine)
        .clamp(0.0, target.position.maxScrollExtent);
    if ((target.offset - nextOffset).abs() < 0.5) return;
    _syncingScroll = true;
    target.jumpTo(nextOffset);
    _syncingScroll = false;
  }

  /// Lines both panes should agree on. Null while the target is not laid out or
  /// fits without scrolling, where either its metrics or the scrolling itself
  /// would be meaningless.
  _PaneScrollMetrics? _paneMetrics(ScrollController scroller, int lineCount) {
    if (lineCount <= 0 || !scroller.hasClients) return null;
    final position = scroller.position;
    // Below this the content is shorter than the viewport and the extent no
    // longer describes the text.
    if (position.maxScrollExtent <= 0) return null;
    final content = position.maxScrollExtent + position.viewportDimension;
    final usable = content - _editorPaddingTop - _editorPaddingBottom;
    if (usable <= 0) return null;
    return _PaneScrollMetrics(
      lineHeight: usable / lineCount,
      topPadding: _editorPaddingTop,
    );
  }

  CodeScrollController _scrollControllerFor(TextCompareSide side) =>
      side == TextCompareSide.left
      ? _leftScrollController
      : _rightScrollController;

  /// Mirrors a scroll performed inside one of the WebView editors.
  ///
  /// The DOM reports the character offset at the top of the viewport; that
  /// offset becomes a line, the line becomes its counterpart, and the
  /// counterpart becomes the offset the other pane scrolls to.
  void _webScrollChanged(TextCompareSide side, int topOffset) {
    if (!_syncScrollEnabled) return;
    final result = widget.controller.result;
    if (result == null) return;
    final map = side == TextCompareSide.left
        ? result.leftToRight
        : result.rightToLeft;
    if (map.isEmpty) return;
    final sourceText = _findText(side);
    final targetText = _findText(side.opposite);
    if (sourceText.isEmpty || targetText.isEmpty) return;
    final index = _lineIndexAt(sourceText, topOffset);
    if (index < 0 || index >= map.length) return;
    final paired = map[index];
    if (paired < 0) return;
    _webEditorControllerFor(
      side.opposite,
    ).scrollOffsetToTop(_lineStartOffset(targetText, paired));
  }

  /// Index of the line that contains [offset].
  ///
  /// This runs once per scroll frame, so it jumps between newlines instead of
  /// walking every character.
  int _lineIndexAt(String text, int offset) {
    final limit = offset.clamp(0, text.length);
    var line = 0;
    var index = 0;
    while (index < limit) {
      final next = text.indexOf('\n', index);
      if (next < 0 || next >= limit) break;
      line++;
      index = next + 1;
    }
    return line;
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
    final nextResult = widget.controller.result;
    if (!identical(nextResult, _syncedResult)) {
      // A new result renumbers every diff, so the navigation cursor and the
      // lines kept unfolded for it are stale.
      _syncedResult = nextResult;
      _diffIndex = -1;
      _revealedLeftLines.clear();
      _revealedRightLines.clear();
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

  void _setSyncScroll(bool value) {
    if (_syncScrollEnabled == value) return;
    setState(() => _syncScrollEnabled = value);
    if (!value) return;
    // Turning it back on should line the panes up straight away, using the
    // pane the user last interacted with as the reference.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncVerticalScroll(_activeEditorSide);
    });
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
    final leftCount = _collapseUnchangedRuns(
      _leftEditor,
      result.leftLines,
      _revealedLeftLines,
    );
    final rightCount = _collapseUnchangedRuns(
      _rightEditor,
      result.rightLines,
      _revealedRightLines,
    );
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
    Set<int> keepVisible,
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
        if (end > start + 1 &&
            !_containsKeptLine(runStart, runEnd, keepVisible)) {
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

  /// A run the user just jumped into stays open so the difference it holds is
  /// actually visible.
  bool _containsKeptLine(int start, int end, Set<int> keepVisible) {
    if (keepVisible.isEmpty) return false;
    for (final line in keepVisible) {
      if (line >= start && line <= end) return true;
    }
    return false;
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
    _focusRestorer.active =
        Visibility.of(context) && (!_usesWebEditor || _findSessionActive);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            widget.controller.compare,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            widget.controller.compare,
        const SingleActivator(LogicalKeyboardKey.f7): _goToNextDiff,
        const SingleActivator(LogicalKeyboardKey.f7, shift: true):
            _goToPreviousDiff,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _openFind(_activeEditorSide),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _openFind(_activeEditorSide),
        if (_findVisible)
          const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
        if (_findVisible)
          const SingleActivator(LogicalKeyboardKey.arrowDown): _nextFindMatch,
      },
      child: Focus(
        focusNode: _pageFocusNode,
        autofocus: true,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  CompareToolbar(
                    controller: widget.controller,
                    foldUnchanged: _foldUnchanged,
                    showFoldUnchanged: !_usesWebEditor,
                    onFoldUnchangedChanged: _setFoldUnchanged,
                    syncScroll: _syncScrollEnabled,
                    onSyncScrollChanged: _setSyncScroll,
                    onOpenLeft: () => _openFile(TextCompareSide.left),
                    onOpenRight: () => _openFile(TextCompareSide.right),
                    onCopySummary: _copySummary,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: CompareTextPane(
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
                              webEditorController: _leftWebEditorController,
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
                              onWebScrollChanged: (offset) => _webScrollChanged(
                                TextCompareSide.left,
                                offset,
                              ),
                              onChanged: (_) => widget.controller.updateLeft(
                                _leftEditor.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CompareTextPane(
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
                              webEditorController: _rightWebEditorController,
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
                              onWebScrollChanged: (offset) => _webScrollChanged(
                                TextCompareSide.right,
                                offset,
                              ),
                              onChanged: (_) => widget.controller.updateRight(
                                _rightEditor.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  CompareStatusBar(
                    controller: widget.controller,
                    diffIndex: _diffIndex,
                    foldUnchanged: _foldUnchanged,
                    foldedLineCount: _foldedLineCount,
                    onPreviousDiff: _goToPreviousDiff,
                    onNextDiff: _goToNextDiff,
                  ),
                ],
              ),
              if (_findVisible)
                Positioned(
                  top: 54,
                  right: 16,
                  child: CompareFindPanel(
                    key: const ValueKey('text-compare-find-panel'),
                    controller: _findInputController,
                    focusNode: _findFocusNode,
                    inputKey: const ValueKey('text-compare-find-input'),
                    matchSide:
                        _findMatchIndex < 0 ||
                            _findMatchIndex >= _findMatches.length
                        ? null
                        : _findMatches[_findMatchIndex].side,
                    matchIndex: _findMatchIndex,
                    matchCount: _findMatches.length,
                    onFocus: _onFindFocusChanged,
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
