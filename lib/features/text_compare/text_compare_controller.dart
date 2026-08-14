import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'text_compare_models.dart';
import 'text_compare_service.dart';

const textCompareMaxBytes = 10 * 1024 * 1024;

class TextCompareController extends ChangeNotifier {
  TextCompareController({TextCompareService? service})
    : _service = service ?? const IsolateTextCompareService();

  final TextCompareService _service;

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
    _invalidateResult();
  }

  void updateIgnoreTrailingWhitespace(bool value) {
    if (options.ignoreTrailingWhitespace == value) return;
    options = options.copyWith(ignoreTrailingWhitespace: value);
    _invalidateResult();
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
    if (isComparing) return;
    if (!canCompare) {
      _setError('请先输入或打开要比对的文本');
      return;
    }
    if (leftBytes > textCompareMaxBytes || rightBytes > textCompareMaxBytes) {
      _setError('单侧文本不能超过 10 MiB');
      return;
    }
    final requestVersion = ++_requestVersion;
    final contentVersion = _contentVersion;
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
      if (requestVersion != _requestVersion ||
          contentVersion != _contentVersion) {
        return;
      }
      result = nextResult;
      status = nextResult.hasChanges
          ? TextCompareStatus.changed
          : TextCompareStatus.unchanged;
      highlightRevision++;
    } on Object {
      if (requestVersion != _requestVersion ||
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
        notifyListeners();
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
    final rules = <String>[
      if (options.ignoreCase) '忽略大小写',
      if (options.ignoreTrailingWhitespace) '忽略行尾空白',
    ];
    final outcome = current.hasChanges
        ? '新增 ${current.addedCount} 行，删除 ${current.removedCount} 行，修改 ${current.modifiedCount} 行'
        : '未发现差异';
    return [
      '文本比对结果',
      outcome,
      '左侧：$leftFileName',
      '右侧：$rightFileName',
      '规则：${rules.isEmpty ? '精确比较' : rules.join('、')}',
    ].join('\n');
  }

  void _invalidateResult({bool forceIdle = false}) {
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
  }

  void _setError(String message) {
    result = null;
    status = TextCompareStatus.error;
    errorMessage = message;
    highlightRevision++;
    notifyListeners();
  }
}
