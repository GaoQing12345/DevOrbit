import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'sql_log_converter.dart';

/// Runs the log→SQL conversion somewhere other than the UI isolate.
abstract interface class SqlLogConversionService {
  Future<SqlLogConversionResult> convert(String source, SqlLogDialect dialect);
}

/// Default service: conversion runs in a short-lived isolate.
///
/// A 2 MB MyBatis log takes roughly 100 ms to parse. Doing that on the UI
/// isolate after every debounce tick drops frames while the user is still
/// editing, so the work moves out and the result is applied when it lands.
class IsolateSqlLogConversionService implements SqlLogConversionService {
  const IsolateSqlLogConversionService();

  @override
  Future<SqlLogConversionResult> convert(String source, SqlLogDialect dialect) {
    return Isolate.run(
      () => const SqlLogConverter().convert(source, dialect: dialect),
    );
  }
}

class SqlLogController extends ChangeNotifier {
  SqlLogController({
    this.converter = const SqlLogConverter(),
    this.conversion = const IsolateSqlLogConversionService(),
  });

  /// Recognises supported log formats; the conversion itself runs through
  /// [conversion] so callers can keep it on the calling isolate in tests.
  final SqlLogConverter converter;
  final SqlLogConversionService conversion;
  Timer? _conversionTimer;
  String _sourceText = '';
  SqlLogDialect _dialect = SqlLogDialect.mysql;
  SqlLogConversionResult _result = SqlLogConversionResult.empty;
  int _generation = 0;
  bool _disposed = false;

  String get sourceText => _sourceText;
  SqlLogDialect get dialect => _dialect;
  SqlLogConversionResult get result => _result;

  void updateSource(String value, {bool immediate = false}) {
    final changed = value != _sourceText;
    _sourceText = value;
    _conversionTimer?.cancel();
    if (changed) notifyListeners();
    if (immediate) {
      unawaited(convertNow());
    } else {
      _conversionTimer = Timer(
        const Duration(milliseconds: 160),
        () => unawaited(convertNow()),
      );
    }
  }

  void setDialect(SqlLogDialect dialect) {
    if (_dialect == dialect) return;
    _dialect = dialect;
    unawaited(convertNow());
  }

  Future<bool> importRecognizedLog(String value) async {
    if (!converter.looksLikeSupportedLog(value)) return false;
    _conversionTimer?.cancel();
    _conversionTimer = null;
    _sourceText = value;
    notifyListeners();
    await convertNow();
    return true;
  }

  /// Recomputes the SQL preview.
  ///
  /// Awaitable so clipboard import and tests can observe the new result. A
  /// conversion that finishes after the input moved on is discarded instead of
  /// painting an older document.
  Future<void> convertNow() async {
    _conversionTimer?.cancel();
    _conversionTimer = null;
    final generation = ++_generation;
    final source = _sourceText;
    final dialect = _dialect;
    final result = source.trim().isEmpty
        ? SqlLogConversionResult.empty
        : await conversion.convert(source, dialect);
    if (_disposed || generation != _generation) return;
    _result = result;
    notifyListeners();
  }

  void clear() {
    _conversionTimer?.cancel();
    _conversionTimer = null;
    // A conversion in flight would otherwise resurrect the cleared text.
    _generation++;
    _sourceText = '';
    _result = SqlLogConversionResult.empty;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _conversionTimer?.cancel();
    super.dispose();
  }
}
