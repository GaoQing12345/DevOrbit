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
  JsonIssue? _issue;
  JsonDocumentStatus _status = JsonDocumentStatus.empty;
  int _revision = 0;

  String get text => _text;
  String? get filePath => _filePath;
  bool get isDirty => _isDirty;
  bool get isBusy => _isBusy;
  JsonIssue? get issue => _issue;
  JsonDocumentStatus get status => _status;

  void userEdit(String value) {
    if (value == _text) return;
    _text = value;
    _isDirty = true;
    _revision++;
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
    _revision++;
    notifyListeners();
    await validate();
    return true;
  }

  Future<bool> importClipboard(String value, int indentSize) async {
    if (_isDirty || value.trim().isEmpty || value == _text) return false;
    final result = await transformer.run(
      value,
      JsonTransformMode.format,
      indentSize: indentSize,
    );
    if (!result.isValid) return false;
    _text = result.output!;
    _filePath = null;
    _isDirty = false;
    _issue = null;
    _status = JsonDocumentStatus.valid;
    _revision++;
    notifyListeners();
    return true;
  }

  Future<bool> transform(JsonTransformMode mode, int indentSize) async {
    if (_isBusy) return false;
    final source = _text;
    final revision = _revision;
    _isBusy = true;
    _status = JsonDocumentStatus.validating;
    notifyListeners();
    final result = await transformer.run(source, mode, indentSize: indentSize);
    if (revision != _revision) {
      _isBusy = false;
      notifyListeners();
      return false;
    }
    _isBusy = false;
    if (!result.isValid) {
      _setIssue(result.issue!);
      return false;
    }
    if (mode != JsonTransformMode.validate) {
      _text = result.output!;
      _isDirty = true;
      _revision++;
    }
    _issue = null;
    _status = JsonDocumentStatus.valid;
    notifyListeners();
    return true;
  }

  Future<void> validate() async {
    final source = _text;
    final revision = _revision;
    if (source.trim().isEmpty) {
      _status = JsonDocumentStatus.empty;
      _issue = null;
      notifyListeners();
      return;
    }
    _status = JsonDocumentStatus.validating;
    notifyListeners();
    final result = await transformer.run(source, JsonTransformMode.validate);
    if (revision != _revision) return;
    if (result.isValid) {
      _status = JsonDocumentStatus.valid;
      _issue = null;
      notifyListeners();
    } else {
      _setIssue(result.issue!);
    }
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
    _validationTimer?.cancel();
    super.dispose();
  }
}
