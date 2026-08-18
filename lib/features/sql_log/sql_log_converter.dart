import 'package:sql_formatter/sql_formatter.dart' as sql_formatter;

enum SqlLogDialect {
  mysql('MySQL'),
  standard('标准 SQL'),
  postgresql('PostgreSQL'),
  sqlite('SQLite');

  const SqlLogDialect(this.label);

  final String label;

  sql_formatter.SqlDialect get formatterDialect => switch (this) {
    SqlLogDialect.mysql => sql_formatter.SqlDialect.mysql,
    SqlLogDialect.standard => sql_formatter.SqlDialect.standard,
    SqlLogDialect.postgresql => sql_formatter.SqlDialect.postgresql,
    SqlLogDialect.sqlite => sql_formatter.SqlDialect.sqlite,
  };
}

class SqlLogParameter {
  const SqlLogParameter({required this.value, required this.type});

  final String value;
  final String? type;

  String toSqlLiteral() {
    final trimmedValue = value.trim();
    if (trimmedValue.toLowerCase() == 'null') return 'NULL';

    final normalizedType = _normalizedType(type);
    if (_numericTypes.contains(normalizedType)) return trimmedValue;
    if (_booleanTypes.contains(normalizedType)) {
      final normalizedValue = trimmedValue.toLowerCase();
      if (normalizedValue == 'true' || normalizedValue == 'false') {
        return normalizedValue.toUpperCase();
      }
      if (normalizedValue == '1' || normalizedValue == '0') {
        return normalizedValue;
      }
    }
    return "'${trimmedValue.replaceAll("'", "''")}'";
  }

  static String _normalizedType(String? type) {
    if (type == null) return '';
    final withoutGenerics = type.trim().split('<').first;
    return withoutGenerics.split('.').last.toLowerCase();
  }

  static const _numericTypes = {
    'byte',
    'short',
    'integer',
    'int',
    'long',
    'biginteger',
    'float',
    'double',
    'decimal',
    'bigdecimal',
    'number',
    'atomicinteger',
    'atomiclong',
  };

  static const _booleanTypes = {'bool', 'boolean'};
}

class SqlLogStatementResult {
  const SqlLogStatementResult({
    required this.rawSql,
    required this.parameters,
    required this.formattedSql,
    required this.placeholderCount,
    required this.substitutedCount,
    required this.warnings,
  });

  final String rawSql;
  final List<SqlLogParameter> parameters;
  final String formattedSql;
  final int placeholderCount;
  final int substitutedCount;
  final List<String> warnings;
}

class SqlLogConversionResult {
  const SqlLogConversionResult({
    required this.statements,
    required this.diagnostics,
  });

  static const empty = SqlLogConversionResult(
    statements: <SqlLogStatementResult>[],
    diagnostics: <String>[],
  );

  final List<SqlLogStatementResult> statements;
  final List<String> diagnostics;

  String get output => statements
      .map((statement) => statement.formattedSql)
      .where((sql) => sql.isNotEmpty)
      .join('\n\n');

  int get warningCount =>
      diagnostics.length +
      statements.fold(
        0,
        (count, statement) => count + statement.warnings.length,
      );

  List<String> get allWarnings => [
    ...diagnostics,
    for (final statement in statements) ...statement.warnings,
  ];
}

class SqlLogConverter {
  const SqlLogConverter();

  static final _preparingMarker = RegExp(
    r'\bPreparing\s*:\s*',
    caseSensitive: false,
  );
  static final _parametersMarker = RegExp(
    r'\bParameters\s*:\s*',
    caseSensitive: false,
  );
  static final _logTimestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\s',
  );
  static final _typePattern = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_.$]*(?:\[\])?(?:<[^<>]+>)?$',
  );
  static final _sqlStart = RegExp(
    r'^\s*(?:SELECT|INSERT|UPDATE|DELETE|WITH|MERGE|REPLACE|CALL)\b',
    caseSensitive: false,
  );

  bool looksLikeSupportedLog(String source) {
    if (!_parametersMarker.hasMatch(source)) return false;
    if (_preparingMarker.hasMatch(source)) return true;
    return _normalizedLines(source).any(_looksLikeRawSqlLine);
  }

  SqlLogConversionResult convert(
    String source, {
    SqlLogDialect dialect = SqlLogDialect.mysql,
  }) {
    if (source.trim().isEmpty) return SqlLogConversionResult.empty;

    final diagnostics = <String>[];
    final rawStatements = _extractStatements(source, diagnostics);
    final statements = <SqlLogStatementResult>[];

    for (var index = 0; index < rawStatements.length; index++) {
      final raw = rawStatements[index];
      final displayIndex = index + 1;
      final warnings = <String>[];
      final parameterResult = raw.parameters == null
          ? const _ParameterParseResult(parameters: [], warnings: [])
          : _parseParameters(raw.parameters!);
      warnings.addAll(
        parameterResult.warnings.map(
          (warning) => '第 $displayIndex 条 SQL：$warning',
        ),
      );
      if (raw.parameters == null) {
        warnings.add('第 $displayIndex 条 SQL 未找到 Parameters 报文');
      }

      final replacement = _replacePlaceholders(
        raw.sql,
        parameterResult.parameters,
        dialect,
      );
      if (replacement.placeholderCount > parameterResult.parameters.length) {
        warnings.add(
          '第 $displayIndex 条 SQL 有 ${replacement.placeholderCount} 个占位符，'
          '只有 ${parameterResult.parameters.length} 个参数；未匹配的 ? 已保留',
        );
      } else if (parameterResult.parameters.length >
          replacement.placeholderCount) {
        warnings.add(
          '第 $displayIndex 条 SQL 有 ${replacement.placeholderCount} 个占位符，'
          '但提供了 ${parameterResult.parameters.length} 个参数；多余参数未使用',
        );
      }

      final formatted = _formatSql(replacement.sql, dialect);
      statements.add(
        SqlLogStatementResult(
          rawSql: raw.sql,
          parameters: List.unmodifiable(parameterResult.parameters),
          formattedSql: formatted,
          placeholderCount: replacement.placeholderCount,
          substitutedCount: replacement.substitutedCount,
          warnings: List.unmodifiable(warnings),
        ),
      );
    }

    if (statements.isEmpty && diagnostics.isEmpty) {
      diagnostics.add('没有找到可识别的 SQL 报文');
    }
    return SqlLogConversionResult(
      statements: List.unmodifiable(statements),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  List<_RawSqlLogStatement> _extractStatements(
    String source,
    List<String> diagnostics,
  ) {
    final statements = <_RawSqlLogStatement>[];
    _PendingSqlLogStatement? pending;
    final lines = _normalizedLines(source);

    void finishPending() {
      final current = pending;
      if (current == null) return;
      final sql = current.sqlLines.join('\n').trim();
      if (sql.isNotEmpty) {
        statements.add(
          _RawSqlLogStatement(
            sql: sql,
            parameters: current.parameterLines == null
                ? null
                : _cleanParameterText(current.parameterLines!.join(' ')),
          ),
        );
      } else {
        diagnostics.add('第 ${current.lineNumber} 行的 Preparing 报文没有 SQL 内容');
      }
      pending = null;
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final preparing = _preparingMarker.firstMatch(line);
      if (preparing != null) {
        finishPending();
        pending = _PendingSqlLogStatement(
          lineNumber: index + 1,
          sqlLines: [line.substring(preparing.end).trim()],
        );
        continue;
      }

      final parameters = _parametersMarker.firstMatch(line);
      if (parameters != null) {
        final current = pending;
        if (current == null) {
          diagnostics.add('第 ${index + 1} 行的 Parameters 报文没有对应的 Preparing');
        } else if (current.parameterLines != null) {
          finishPending();
          diagnostics.add('第 ${index + 1} 行的 Parameters 报文没有对应的 Preparing');
        } else {
          current.parameterLines = [line.substring(parameters.end).trim()];
        }
        continue;
      }

      if ((pending == null || pending!.parameterLines != null) &&
          _looksLikeRawSqlLine(line)) {
        finishPending();
        pending = _PendingSqlLogStatement(
          lineNumber: index + 1,
          sqlLines: [line.trim()],
        );
        continue;
      }

      final current = pending;
      if (current == null) continue;
      if (current.parameterLines == null) {
        if (_isSqlContinuation(line)) current.sqlLines.add(line.trim());
      } else if (current.parameterLines!.last.trimRight().endsWith(',') &&
          _isIndentedContinuation(line)) {
        current.parameterLines!.add(line.trim());
      }
    }

    finishPending();
    return statements;
  }

  List<String> _normalizedLines(String source) =>
      source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  bool _looksLikeRawSqlLine(String line) => _sqlStart.hasMatch(line);

  bool _isSqlContinuation(String line) {
    final trimmed = line.trim();
    if (_looksLikeSeparateLogLine(line)) return false;
    if (line.isNotEmpty && line.codeUnitAt(0) <= 0x20) return true;
    return RegExp(
      r'^(?:SELECT|INSERT|UPDATE|DELETE|WITH|FROM|WHERE|AND|OR|JOIN|LEFT|RIGHT|INNER|OUTER|FULL|CROSS|ON|GROUP|ORDER|HAVING|LIMIT|OFFSET|VALUES|SET|RETURNING|UNION|EXCEPT|INTERSECT)\b',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  bool _isIndentedContinuation(String line) {
    return line.isNotEmpty &&
        line.codeUnitAt(0) <= 0x20 &&
        !_looksLikeSeparateLogLine(line);
  }

  bool _looksLikeSeparateLogLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.contains('==>') || trimmed.contains('<==')) {
      return true;
    }
    if (_logTimestamp.hasMatch(trimmed)) return true;
    return RegExp(
          r'\s(?:TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\s',
        ).hasMatch(line) &&
        line.contains(' - ');
  }

  String _cleanParameterText(String value) {
    return value.trim().replaceFirst(RegExp(r'\s*[。；]\s*$'), '');
  }

  _ParameterParseResult _parseParameters(String source) {
    final trimmed = _cleanParameterText(source);
    if (trimmed.isEmpty) {
      return const _ParameterParseResult(parameters: [], warnings: []);
    }

    final parameters = <SqlLogParameter>[];
    final warnings = <String>[];
    var tokenStart = 0;

    void addToken(String token) {
      final value = token.trim();
      if (value.isEmpty) return;
      final parameter = _parseCompleteParameter(value);
      if (parameter != null) {
        parameters.add(parameter);
        return;
      }
      parameters.add(SqlLogParameter(value: value, type: null));
      warnings.add('参数“$value”缺少可识别的类型，已按字符串处理');
    }

    for (var index = 0; index < trimmed.length; index++) {
      if (trimmed.codeUnitAt(index) != 0x2c) continue;
      final candidate = trimmed.substring(tokenStart, index).trim();
      if (!_isCompleteParameterToken(candidate)) continue;
      addToken(candidate);
      tokenStart = index + 1;
    }
    addToken(trimmed.substring(tokenStart));

    return _ParameterParseResult(parameters: parameters, warnings: warnings);
  }

  bool _isCompleteParameterToken(String value) {
    return value.toLowerCase() == 'null' ||
        _parseCompleteParameter(value) != null;
  }

  SqlLogParameter? _parseCompleteParameter(String token) {
    if (token.toLowerCase() == 'null') {
      return const SqlLogParameter(value: 'null', type: null);
    }
    if (!token.endsWith(')')) return null;
    final typeStart = token.lastIndexOf('(');
    if (typeStart < 0) return null;
    final type = token.substring(typeStart + 1, token.length - 1).trim();
    if (!_looksLikeJavaType(type)) return null;
    return SqlLogParameter(
      value: token.substring(0, typeStart).trim(),
      type: type,
    );
  }

  bool _looksLikeJavaType(String type) {
    if (!_typePattern.hasMatch(type)) return false;
    final base = type.split('<').first.split('.').last.replaceAll('[]', '');
    if (base.isEmpty) return false;
    if (_primitiveTypes.contains(base.toLowerCase())) return true;
    return type.contains('.') || _isUpperAscii(base.codeUnitAt(0));
  }

  bool _isUpperAscii(int codeUnit) => codeUnit >= 0x41 && codeUnit <= 0x5a;

  _PlaceholderReplacement _replacePlaceholders(
    String sql,
    List<SqlLogParameter> parameters,
    SqlLogDialect dialect,
  ) {
    final buffer = StringBuffer();
    var state = _SqlScanState.normal;
    String? dollarQuote;
    var parameterIndex = 0;
    var placeholderCount = 0;

    for (var index = 0; index < sql.length; index++) {
      if (state == _SqlScanState.dollarQuote) {
        if (dollarQuote != null && sql.startsWith(dollarQuote, index)) {
          buffer.write(dollarQuote);
          index += dollarQuote.length - 1;
          state = _SqlScanState.normal;
          dollarQuote = null;
        } else {
          buffer.writeCharCode(sql.codeUnitAt(index));
        }
        continue;
      }

      final current = sql.codeUnitAt(index);
      final next = index + 1 < sql.length ? sql.codeUnitAt(index + 1) : null;

      if (state == _SqlScanState.lineComment) {
        buffer.writeCharCode(current);
        if (current == 0x0a) state = _SqlScanState.normal;
        continue;
      }
      if (state == _SqlScanState.blockComment) {
        buffer.writeCharCode(current);
        if (current == 0x2a && next == 0x2f) {
          buffer.writeCharCode(next!);
          index++;
          state = _SqlScanState.normal;
        }
        continue;
      }
      if (state != _SqlScanState.normal) {
        buffer.writeCharCode(current);
        final quote = switch (state) {
          _SqlScanState.singleQuote => 0x27,
          _SqlScanState.doubleQuote => 0x22,
          _SqlScanState.backtick => 0x60,
          _SqlScanState.bracketIdentifier => 0x5d,
          _ => -1,
        };
        if (current == 0x5c && next != null) {
          buffer.writeCharCode(next);
          index++;
        } else if (current == quote) {
          if (next == quote) {
            buffer.writeCharCode(next!);
            index++;
          } else {
            state = _SqlScanState.normal;
          }
        }
        continue;
      }

      if (current == 0x2d && next == 0x2d) {
        buffer.write('--');
        index++;
        state = _SqlScanState.lineComment;
        continue;
      }
      if (current == 0x2f && next == 0x2a) {
        buffer.write('/*');
        index++;
        state = _SqlScanState.blockComment;
        continue;
      }
      if (current == 0x23 && dialect == SqlLogDialect.mysql) {
        buffer.writeCharCode(current);
        state = _SqlScanState.lineComment;
        continue;
      }
      if (current == 0x27) {
        buffer.writeCharCode(current);
        state = _SqlScanState.singleQuote;
        continue;
      }
      if (current == 0x22) {
        buffer.writeCharCode(current);
        state = _SqlScanState.doubleQuote;
        continue;
      }
      if (current == 0x60) {
        buffer.writeCharCode(current);
        state = _SqlScanState.backtick;
        continue;
      }
      if (current == 0x5b) {
        buffer.writeCharCode(current);
        state = _SqlScanState.bracketIdentifier;
        continue;
      }
      if (current == 0x24 && dialect == SqlLogDialect.postgresql) {
        final delimiter = _readDollarQuoteDelimiter(sql, index);
        if (delimiter != null) {
          buffer.write(delimiter);
          index += delimiter.length - 1;
          dollarQuote = delimiter;
          state = _SqlScanState.dollarQuote;
          continue;
        }
      }
      if (current == 0x3f) {
        if (dialect == SqlLogDialect.postgresql &&
            (next == 0x7c || next == 0x26)) {
          buffer.writeCharCode(current);
          continue;
        }
        placeholderCount++;
        if (parameterIndex < parameters.length) {
          buffer.write(parameters[parameterIndex].toSqlLiteral());
          parameterIndex++;
        } else {
          buffer.writeCharCode(current);
        }
        continue;
      }
      buffer.writeCharCode(current);
    }

    return _PlaceholderReplacement(
      sql: buffer.toString(),
      placeholderCount: placeholderCount,
      substitutedCount: parameterIndex,
    );
  }

  String? _readDollarQuoteDelimiter(String sql, int start) {
    final end = sql.indexOf(r'$', start + 1);
    if (end < 0) return null;
    final tag = sql.substring(start + 1, end);
    if (tag.isNotEmpty && !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(tag)) {
      return null;
    }
    return sql.substring(start, end + 1);
  }

  String _formatSql(String sql, SqlLogDialect dialect) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return '';
    var protectedSql = trimmed;
    if (dialect == SqlLogDialect.postgresql) {
      protectedSql = protectedSql
          .replaceAll('?|', _postgresAnyKeyToken)
          .replaceAll('?&', _postgresAllKeysToken);
    }
    var formatted = sql_formatter
        .format(
          protectedSql,
          dialect: dialect.formatterDialect,
          options: const sql_formatter.FormatOptions(
            indent: '  ',
            keywordCase: sql_formatter.KeywordCase.upper,
            linesBetweenQueries: 1,
          ),
        )
        .trim();
    if (dialect == SqlLogDialect.postgresql) {
      formatted = formatted
          .replaceAll(_postgresAnyKeyToken, '?|')
          .replaceAll(_postgresAllKeysToken, '?&');
    }
    if (formatted.isEmpty || formatted.endsWith(';')) return formatted;
    return '$formatted;';
  }

  static const _postgresAnyKeyToken = '__DEV_ORBIT_PG_ANY_KEY_OPERATOR__';
  static const _postgresAllKeysToken = '__DEV_ORBIT_PG_ALL_KEYS_OPERATOR__';

  static const _primitiveTypes = {
    'byte',
    'short',
    'integer',
    'int',
    'long',
    'float',
    'double',
    'boolean',
    'bool',
    'char',
  };
}

class _RawSqlLogStatement {
  const _RawSqlLogStatement({required this.sql, required this.parameters});

  final String sql;
  final String? parameters;
}

class _PendingSqlLogStatement {
  _PendingSqlLogStatement({required this.lineNumber, required this.sqlLines});

  final int lineNumber;
  final List<String> sqlLines;
  List<String>? parameterLines;
}

class _ParameterParseResult {
  const _ParameterParseResult({
    required this.parameters,
    required this.warnings,
  });

  final List<SqlLogParameter> parameters;
  final List<String> warnings;
}

class _PlaceholderReplacement {
  const _PlaceholderReplacement({
    required this.sql,
    required this.placeholderCount,
    required this.substitutedCount,
  });

  final String sql;
  final int placeholderCount;
  final int substitutedCount;
}

enum _SqlScanState {
  normal,
  singleQuote,
  doubleQuote,
  backtick,
  bracketIdentifier,
  lineComment,
  blockComment,
  dollarQuote,
}
