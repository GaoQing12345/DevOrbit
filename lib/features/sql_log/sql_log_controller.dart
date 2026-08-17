import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sql_log_converter.dart';

class SqlLogController extends ChangeNotifier {
  SqlLogController([this._converter = const SqlLogConverter()]);

  final SqlLogConverter _converter;
  Timer? _conversionTimer;
  String _sourceText = '';
  SqlLogDialect _dialect = SqlLogDialect.mysql;
  SqlLogConversionResult _result = SqlLogConversionResult.empty;

  String get sourceText => _sourceText;
  SqlLogDialect get dialect => _dialect;
  SqlLogConversionResult get result => _result;

  void updateSource(String value, {bool immediate = false}) {
    final changed = value != _sourceText;
    _sourceText = value;
    _conversionTimer?.cancel();
    if (changed) notifyListeners();
    if (immediate) {
      convertNow();
    } else {
      _conversionTimer = Timer(const Duration(milliseconds: 160), convertNow);
    }
  }

  void setDialect(SqlLogDialect dialect) {
    if (_dialect == dialect) return;
    _dialect = dialect;
    convertNow();
  }

  bool importRecognizedLog(String value) {
    if (!_converter.looksLikeSupportedLog(value)) return false;
    updateSource(value, immediate: true);
    return true;
  }

  void convertNow() {
    _conversionTimer?.cancel();
    _conversionTimer = null;
    _result = _converter.convert(_sourceText, dialect: _dialect);
    notifyListeners();
  }

  void clear() {
    _conversionTimer?.cancel();
    _conversionTimer = null;
    _sourceText = '';
    _result = SqlLogConversionResult.empty;
    notifyListeners();
  }

  @override
  void dispose() {
    _conversionTimer?.cancel();
    super.dispose();
  }
}
