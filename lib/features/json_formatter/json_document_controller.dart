import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'json_transformer.dart';

enum JsonDocumentStatus { empty, validating, valid, invalid }

class JsonDocumentController extends ChangeNotifier {
  JsonDocumentController({this.transformer = const JsonTransformer()});

  final JsonTransformer transformer;
  Timer? _validationTimer;
  String _text = '';
  String? _filePath;
  bool _isDirty = false;
  bool _isBusy = false;
  bool _isValidating = false;
  bool _validationPending = false;
  bool _repaired = false;
  bool _disposed = false;
  JsonIssue? _issue;
  JsonDocumentStatus _status = JsonDocumentStatus.empty;
  int _revision = 0;

  String get text => _text;
  String? get filePath => _filePath;
  bool get isDirty => _isDirty;
  bool get isBusy => _isBusy;
  bool get isValidating => _isValidating;
  JsonIssue? get issue => _issue;
  JsonDocumentStatus get status => _status;

  /// Whether the current text only passed validation after an automatic repair,
  /// which means the content on screen no longer matches what was pasted.
  bool get repaired => _repaired;

  void userEdit(String value) {
    if (value == _text) return;
    _text = value;
    _isDirty = true;
    _revision++;
    // The repaired marker belongs to the content that produced it.
    _repaired = false;
    _scheduleValidation();
    notifyListeners();
  }

  Future<bool> loadText(String value, {String? filePath}) async {
    if (utf8.encode(value).length > maxJsonBytes) {
      _setIssue(const JsonIssue(message: '内容超过 10 MiB 限制', line: 1, column: 1));
      return false;
    }
    _text = value;
    _filePath = filePath;
    _isDirty = false;
    _repaired = false;
    _revision++;
    notifyListeners();
    await validate();
    return true;
  }

  Future<bool> importClipboard(
    String value,
    int indentSize, {
    bool useTabs = false,
  }) async {
    if (_isDirty || value.trim().isEmpty || value == _text) return false;
    if (utf8.encode(value).length > maxJsonBytes) {
      // Silently ignoring this left the window looking broken, so surface the
      // same message a manual load would.
      _setIssue(const JsonIssue(message: '内容超过 10 MiB 限制', line: 1, column: 1));
      return false;
    }
    final result = await transformer.run(
      value,
      JsonTransformMode.format,
      indentSize: indentSize,
      useTabs: useTabs,
    );
    if (result.output == null) return false;
    _text = result.output!;
    _filePath = null;
    _isDirty = false;
    _repaired = result.repaired;
    _issue = result.issue;
    _status = result.isValid
        ? JsonDocumentStatus.valid
        : JsonDocumentStatus.invalid;
    _revision++;
    notifyListeners();
    return true;
  }

  Future<bool> transform(
    JsonTransformMode mode,
    int indentSize, {
    bool useTabs = false,
  }) async {
    if (_isBusy) return false;
    final source = _text;
    final revision = _revision;
    _isBusy = true;
    _status = JsonDocumentStatus.validating;
    notifyListeners();
    final result = await transformer.run(
      source,
      mode,
      indentSize: indentSize,
      useTabs: useTabs,
    );
    if (revision != _revision) {
      _isBusy = false;
      notifyListeners();
      return false;
    }
    _isBusy = false;
    if (!result.isValid) {
      if (mode != JsonTransformMode.validate &&
          result.output != null &&
          result.output != source) {
        _text = result.output!;
        _isDirty = true;
        _revision++;
      }
      _repaired = false;
      _setIssue(result.issue!);
      return false;
    }
    if (mode != JsonTransformMode.validate) {
      _text = result.output!;
      _isDirty = true;
      _revision++;
    }
    _repaired = result.repaired;
    _issue = null;
    _status = JsonDocumentStatus.valid;
    notifyListeners();
    return true;
  }

  /// Runs [mode] without touching the document, so a copy-only action can use
  /// the result while the editor keeps showing the current layout.
  Future<JsonTransformResult?> previewTransform(
    JsonTransformMode mode,
    int indentSize, {
    bool useTabs = false,
  }) {
    if (_text.trim().isEmpty) return Future.value(null);
    return transformer.run(
      _text,
      mode,
      indentSize: indentSize,
      useTabs: useTabs,
    );
  }

  /// Escapes the document into a string literal. Returns the new text, or null
  /// when nothing changed.
  Future<String?> escapeDocument() => _replaceText(transformer.escape);

  /// Reverses [escapeDocument].
  Future<String?> unescapeDocument() => _replaceText(transformer.unescape);

  Future<String?> _replaceText(
    Future<String> Function(String) transform,
  ) async {
    if (_isBusy || _text.trim().isEmpty) return null;
    final source = _text;
    final revision = _revision;
    _isBusy = true;
    notifyListeners();
    try {
      final next = await transform(source);
      if (revision != _revision || next == source) return null;
      _text = next;
      _isDirty = true;
      _repaired = false;
      _revision++;
      notifyListeners();
      await validate();
      return next;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> validate() async {
    if (_isValidating) {
      // A run is already in flight for an older revision. Queue exactly one
      // follow-up instead of stacking an isolate on every debounce tick.
      _validationPending = true;
      return;
    }
    _isValidating = true;
    try {
      await _runValidation();
      while (_validationPending && !_disposed) {
        _validationPending = false;
        await _runValidation();
      }
    } finally {
      _isValidating = false;
      _validationPending = false;
    }
  }

  Future<void> _runValidation() async {
    final source = _text;
    final revision = _revision;
    if (source.trim().isEmpty) {
      _status = JsonDocumentStatus.empty;
      _issue = null;
      _repaired = false;
      notifyListeners();
      return;
    }
    _status = JsonDocumentStatus.validating;
    notifyListeners();
    final result = await transformer.run(source, JsonTransformMode.validate);
    if (revision != _revision || _disposed) return;
    if (result.isValid) {
      _status = JsonDocumentStatus.valid;
      _issue = null;
      _repaired = result.repaired;
      notifyListeners();
    } else {
      _setIssue(result.issue!);
    }
  }

  /// Offset of the current error inside [text], so the editor can be moved
  /// there. Returns null when the document is not in an error state.
  int? errorOffset() {
    final issue = _issue;
    if (issue == null) return null;
    var line = 1;
    var index = 0;
    while (index < _text.length && line < issue.line) {
      if (_text.codeUnitAt(index) == 10) line++;
      index++;
    }
    // `index` now sits at the start of the error line and the reported column
    // counts code points, so advance that many.
    var column = 1;
    while (index < _text.length && column < issue.column) {
      final unit = _text.codeUnitAt(index);
      if (unit == 10) break;
      index += (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < _text.length)
          ? 2
          : 1;
      column++;
    }
    return index > _text.length ? _text.length : index;
  }

  void markSaved({String? filePath}) {
    _filePath = filePath ?? _filePath;
    _isDirty = false;
    notifyListeners();
  }

  void clear() {
    _validationTimer?.cancel();
    _text = '';
    _filePath = null;
    _isDirty = false;
    _isBusy = false;
    _issue = null;
    _repaired = false;
    _status = JsonDocumentStatus.empty;
    _revision++;
    notifyListeners();
  }

  void _scheduleValidation() {
    _validationTimer?.cancel();
    _validationTimer = Timer(const Duration(milliseconds: 300), validate);
  }

  void _setIssue(JsonIssue issue) {
    _isBusy = false;
    _issue = issue;
    _status = JsonDocumentStatus.invalid;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _validationTimer?.cancel();
    super.dispose();
  }
}
