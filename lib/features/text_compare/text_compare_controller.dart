import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'text_compare_models.dart';
import 'text_compare_service.dart';

const textCompareMaxBytes = 10 * 1024 * 1024;

class TextCompareController extends ChangeNotifier {
  TextCompareController({TextCompareService? service, this.autoCompare = true})
    : _service = service ?? const IsolateTextCompareService();

  /// Delay an edit waits for before a new comparison starts. Long enough to
  /// swallow a burst of keystrokes, short enough to feel live.
  static const Duration autoCompareDelay = Duration(milliseconds: 240);

  final TextCompareService _service;

  /// When true every edit and every rule change refreshes the diff by itself,
  /// the way the desktop comparers behave, instead of waiting for a manual run.
  final bool autoCompare;

  String leftText = '';
  String rightText = '';
  String? leftFilePath;
  String? rightFilePath;
  bool leftDirty = false;
  bool rightDirty = false;
  TextCompareOptions options = const TextCompareOptions();
  TextCompareStatus status = TextCompareStatus.idle;
  TextDiffResult? result;
  String? errorMessage;
  bool isComparing = false;
  int highlightRevision = 0;
  int _contentVersion = 0;
  int _requestVersion = 0;
  int _lastComparedContentVersion = -1;
  Future<void>? _activeCompare;
  Timer? _autoCompareTimer;
  bool _disposed = false;

  String get leftFileName =>
      leftFilePath == null ? '未命名文本' : path.basename(leftFilePath!);

  String get rightFileName =>
      rightFilePath == null ? '未命名文本' : path.basename(rightFilePath!);

  int get leftBytes => utf8.encode(leftText).length;

  int get rightBytes => utf8.encode(rightText).length;

  bool get canCompare =>
      !isComparing && (leftText.isNotEmpty || rightText.isNotEmpty);

  bool get canCopySummary =>
      result != null &&
      (status == TextCompareStatus.changed ||
          status == TextCompareStatus.unchanged);

  /// Change blocks of the current result, used by the diff navigation.
  List<TextDiffHunk> get hunks => result?.hunks ?? const [];

  void updateLeft(String value) {
    if (leftText == value) return;
    leftText = value;
    if (leftFilePath != null) leftDirty = true;
    _invalidateResult();
  }

  void updateRight(String value) {
    if (rightText == value) return;
    rightText = value;
    if (rightFilePath != null) rightDirty = true;
    _invalidateResult();
  }

  void updateIgnoreCase(bool value) {
    if (options.ignoreCase == value) return;
    options = options.copyWith(ignoreCase: value);
    _invalidateResult(immediate: true);
  }

  void updateIgnoreLeadingWhitespace(bool value) {
    if (options.ignoreLeadingWhitespace == value) return;
    options = TextCompareOptions(
      ignoreCase: options.ignoreCase,
      ignoreLeadingWhitespace: value,
      ignoreTrailingWhitespace: options.ignoreTrailingWhitespace,
      // "ignore all whitespace" already covers the edges, so the two edges
      // rules and the catch-all stay mutually exclusive in the toolbar.
      ignoreAllWhitespace: value ? false : options.ignoreAllWhitespace,
      ignoreBlankLines: options.ignoreBlankLines,
      ignoreTrailingNewline: options.ignoreTrailingNewline,
    );
    _invalidateResult(immediate: true);
  }

  void updateIgnoreTrailingWhitespace(bool value) {
    if (options.ignoreTrailingWhitespace == value) return;
    options = TextCompareOptions(
      ignoreCase: options.ignoreCase,
      ignoreLeadingWhitespace: options.ignoreLeadingWhitespace,
      ignoreTrailingWhitespace: value,
      ignoreAllWhitespace: value ? false : options.ignoreAllWhitespace,
      ignoreBlankLines: options.ignoreBlankLines,
      ignoreTrailingNewline: options.ignoreTrailingNewline,
    );
    _invalidateResult(immediate: true);
  }

  void updateIgnoreAllWhitespace(bool value) {
    if (options.ignoreAllWhitespace == value) return;
    options = TextCompareOptions(
      ignoreCase: options.ignoreCase,
      // The catch-all replaces the two edge rules instead of stacking on top
      // of them, so the toolbar never shows two overlapping switches.
      ignoreLeadingWhitespace: value ? false : options.ignoreLeadingWhitespace,
      ignoreTrailingWhitespace: value
          ? false
          : options.ignoreTrailingWhitespace,
      ignoreAllWhitespace: value,
      ignoreBlankLines: options.ignoreBlankLines,
      ignoreTrailingNewline: options.ignoreTrailingNewline,
    );
    _invalidateResult(immediate: true);
  }

  void updateIgnoreBlankLines(bool value) {
    if (options.ignoreBlankLines == value) return;
    options = options.copyWith(ignoreBlankLines: value);
    _invalidateResult(immediate: true);
  }

  void updateIgnoreTrailingNewline(bool value) {
    if (options.ignoreTrailingNewline == value) return;
    options = options.copyWith(ignoreTrailingNewline: value);
    _invalidateResult(immediate: true);
  }

  Future<bool> loadFile(TextCompareSide side, XFile file) async {
    try {
      final length = await file.length();
      if (length > textCompareMaxBytes) {
        _setError('文件不能超过 10 MiB');
        return false;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > textCompareMaxBytes) {
        _setError('文件不能超过 10 MiB');
        return false;
      }
      final text = utf8.decode(bytes);
      if (side == TextCompareSide.left) {
        leftText = text;
        leftFilePath = file.path;
        leftDirty = false;
      } else {
        rightText = text;
        rightFilePath = file.path;
        rightDirty = false;
      }
      _invalidateResult(forceIdle: true);
      return true;
    } on FormatException {
      _setError('无法读取文件：文件不是有效的 UTF-8 文本');
      return false;
    } on Object {
      _setError('无法读取文件');
      return false;
    }
  }

  Future<void> compare() async {
    _cancelAutoCompare();
    // A comparison may already be running because a rule toggle or a previous
    // edit started one. Wait for it instead of silently dropping the request,
    // then run against the current content.
    while (!_disposed && isComparing) {
      final running = _activeCompare;
      if (running == null) break;
      await running;
    }
    if (_disposed) return;
    if (!canCompare) {
      final hadResult = result != null || errorMessage != null;
      result = null;
      errorMessage = null;
      if (status != TextCompareStatus.idle) {
        status = TextCompareStatus.idle;
        highlightRevision++;
      }
      if (hadResult) notifyListeners();
      return;
    }
    if (leftBytes > textCompareMaxBytes || rightBytes > textCompareMaxBytes) {
      _setError('单侧文本不能超过 10 MiB');
      return;
    }
    final request = _runCompare();
    _activeCompare = request;
    await request;
  }

  Future<void> _runCompare() async {
    final requestVersion = ++_requestVersion;
    final contentVersion = _contentVersion;
    _lastComparedContentVersion = contentVersion;
    isComparing = true;
    status = TextCompareStatus.comparing;
    errorMessage = null;
    notifyListeners();
    try {
      final nextResult = await _service.compare(
        left: leftText,
        right: rightText,
        options: options,
      );
      if (_disposed ||
          requestVersion != _requestVersion ||
          contentVersion != _contentVersion) {
        return;
      }
      result = nextResult;
      status = nextResult.hasChanges
          ? TextCompareStatus.changed
          : TextCompareStatus.unchanged;
      highlightRevision++;
    } on Object {
      if (_disposed ||
          requestVersion != _requestVersion ||
          contentVersion != _contentVersion) {
        return;
      }
      result = null;
      status = TextCompareStatus.error;
      errorMessage = '比对失败，请稍后重试';
      highlightRevision++;
    } finally {
      if (requestVersion == _requestVersion) {
        isComparing = false;
        _activeCompare = null;
        if (!_disposed) notifyListeners();
      }
      if (!_disposed && contentVersion != _contentVersion) {
        _scheduleAutoCompare();
      }
    }
  }

  void swap() {
    final oldLeftText = leftText;
    final oldLeftPath = leftFilePath;
    final oldLeftDirty = leftDirty;
    leftText = rightText;
    leftFilePath = rightFilePath;
    leftDirty = rightDirty;
    rightText = oldLeftText;
    rightFilePath = oldLeftPath;
    rightDirty = oldLeftDirty;
    _invalidateResult(forceIdle: true);
  }

  void clear() {
    leftText = '';
    rightText = '';
    leftFilePath = null;
    rightFilePath = null;
    leftDirty = false;
    rightDirty = false;
    _invalidateResult(forceIdle: true);
  }

  String buildSummary() {
    final current = result;
    if (!canCopySummary || current == null) return '';
    final rules = options.ruleLabels;
    final outcome = current.hasChanges
        ? '新增 ${current.addedCount} 行，删除 ${current.removedCount} 行，'
              '修改 ${current.modifiedCount} 行，共 ${current.hunks.length} 处差异'
        : '未发现差异';
    return [
      '文本比对结果',
      outcome,
      '左侧：$leftFileName',
      '右侧：$rightFileName',
      '规则：${rules.isEmpty ? '精确比较' : rules.join('、')}',
    ].join('\n');
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAutoCompare();
    super.dispose();
  }

  void _cancelAutoCompare() {
    _autoCompareTimer?.cancel();
    _autoCompareTimer = null;
  }

  void _scheduleAutoCompare() {
    if (!autoCompare || _disposed) return;
    _cancelAutoCompare();
    _autoCompareTimer = Timer(autoCompareDelay, () {
      _autoCompareTimer = null;
      if (_disposed) return;
      if (isComparing) {
        _scheduleAutoCompare();
        return;
      }
      if (_contentVersion == _lastComparedContentVersion) return;
      unawaited(compare());
    });
  }

  void _invalidateResult({bool forceIdle = false, bool immediate = false}) {
    final hadResult = result != null;
    final previousStatus = status;
    _contentVersion++;
    result = null;
    errorMessage = null;
    if (forceIdle || status == TextCompareStatus.idle) {
      status = TextCompareStatus.idle;
    } else {
      status = TextCompareStatus.stale;
    }
    if (hadResult || previousStatus != status) highlightRevision++;
    notifyListeners();
    if (immediate) {
      unawaited(compare());
    } else {
      _scheduleAutoCompare();
    }
  }

  void _setError(String message) {
    result = null;
    status = TextCompareStatus.error;
    errorMessage = message;
    highlightRevision++;
    notifyListeners();
  }
}
