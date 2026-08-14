import 'dart:convert';
import 'dart:isolate';

import 'package:jsonrepair_dart/jsonrepair_dart.dart';

const maxJsonBytes = 10 * 1024 * 1024;

enum JsonTransformMode { validate, format, compact }

class JsonIssue {
  const JsonIssue({
    required this.message,
    required this.line,
    required this.column,
  });

  final String message;
  final int line;
  final int column;
}

class JsonTransformResult {
  const JsonTransformResult.valid(this.output) : issue = null;
  const JsonTransformResult.invalid(this.issue, {this.output});

  final String? output;
  final JsonIssue? issue;
  bool get isValid => issue == null;
}

class JsonTransformer {
  const JsonTransformer();

  Future<JsonTransformResult> run(
    String source,
    JsonTransformMode mode, {
    int indentSize = 2,
  }) {
    return Isolate.run(() => transformJson(source, mode, indentSize));
  }
}

JsonTransformResult transformJson(
  String source,
  JsonTransformMode mode,
  int indentSize,
) {
  if (utf8.encode(source).length > maxJsonBytes) {
    return const JsonTransformResult.invalid(
      JsonIssue(message: '内容超过 10 MiB 限制', line: 1, column: 1),
    );
  }
  if (source.trim().isEmpty) {
    return const JsonTransformResult.invalid(
      JsonIssue(message: '请输入 JSON 内容', line: 1, column: 1),
    );
  }
  Object? decoded;
  var transformSource = source;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (strictError) {
    final strictIssue = _issueFrom(strictError, source);
    if (mode == JsonTransformMode.validate) {
      return JsonTransformResult.invalid(strictIssue);
    }
    transformSource = _hasNonJsonTextOutsideContainers(source)
        ? ''
        : _repairJsonDocument(source) ?? '';
    if (transformSource.isEmpty) {
      final partialOutput = _transformJsonContainers(source, mode, indentSize);
      return JsonTransformResult.invalid(strictIssue, output: partialOutput);
    }
    decoded = jsonDecode(transformSource);
  }
  if (decoded is! Map && decoded is! List) {
    final contentOffset = source.indexOf(RegExp(r'\S'));
    return JsonTransformResult.invalid(
      _issueAtOffset(
        'JSON 顶层必须是对象或数组',
        source,
        contentOffset < 0 ? 0 : contentOffset,
      ),
    );
  }
  return switch (mode) {
    JsonTransformMode.validate => JsonTransformResult.valid(source),
    JsonTransformMode.format => JsonTransformResult.valid(
      _prettyPrint(transformSource, indentSize),
    ),
    JsonTransformMode.compact => JsonTransformResult.valid(
      _compact(transformSource),
    ),
  };
}

String? _repairJsonDocument(String source) {
  try {
    final repaired = jsonrepair(source);
    final decoded = jsonDecode(repaired);
    if (decoded is Map || decoded is List) return repaired;
  } on JsonRepairError {
    return null;
  } on FormatException {
    return null;
  } on Object {
    return null;
  }
  return null;
}

bool _looksLikeObjectMembers(String source) {
  if (source.isEmpty || source.startsWith('{') || source.startsWith('[')) {
    return false;
  }
  return RegExp(
    r'''^(?:"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|[^\s:,{}\[\]]+)\s*:''',
    dotAll: true,
  ).hasMatch(source);
}

String? _transformJsonContainers(
  String source,
  JsonTransformMode mode,
  int indentSize,
) {
  if (_looksLikeObjectMembers(source.trim())) {
    final transformed = mode == JsonTransformMode.compact
        ? _compact(source)
        : _prettyPrint(source, indentSize);
    return transformed == source ? null : transformed;
  }
  final ranges = _findJsonContainerRanges(source);
  if (ranges.isEmpty) return null;
  final output = StringBuffer();
  var previousEnd = 0;
  var changed = false;
  for (final range in ranges) {
    output.write(source.substring(previousEnd, range.$1));
    final fragment = source.substring(range.$1, range.$2);
    final repaired = _repairJsonDocument(fragment);
    final transformSource = repaired ?? fragment;
    var transformed = mode == JsonTransformMode.compact
        ? _compact(transformSource)
        : _prettyPrint(transformSource, indentSize);
    transformed = _applyLineIndent(transformed, source, range.$1);
    output.write(transformed);
    if (transformed != fragment) changed = true;
    previousEnd = range.$2;
  }
  output.write(source.substring(previousEnd));
  return changed ? output.toString() : null;
}

bool _hasNonJsonTextOutsideContainers(String source) {
  final ranges = _findJsonContainerRanges(source);
  if (ranges.isEmpty) return false;
  final outside = StringBuffer();
  var previousEnd = 0;
  for (final range in ranges) {
    outside.write(source.substring(previousEnd, range.$1));
    previousEnd = range.$2;
  }
  outside.write(source.substring(previousEnd));
  final remaining = outside
      .toString()
      .replaceAll(RegExp(r'```[A-Za-z0-9_-]*'), '')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\r\n]*'), '')
      .trim();
  return remaining.isNotEmpty;
}

List<(int, int)> _findJsonContainerRanges(String source) {
  final ranges = <(int, int)>[];
  final stack = <String>[];
  int? start;
  String? quote;
  var escaped = false;
  var lineComment = false;
  var blockComment = false;

  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';
    if (lineComment) {
      if (char == '\n' || char == '\r') lineComment = false;
      continue;
    }
    if (blockComment) {
      if (char == '*' && next == '/') {
        blockComment = false;
        index++;
      }
      continue;
    }
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '/' && next == '/') {
      lineComment = true;
      index++;
      continue;
    }
    if (char == '/' && next == '*') {
      blockComment = true;
      index++;
      continue;
    }
    if (char == '{' || char == '[') {
      start ??= index;
      stack.add(char);
      continue;
    }
    if ((char == '}' || char == ']') && stack.isNotEmpty) {
      final opening = stack.last;
      final matches =
          (opening == '{' && char == '}') || (opening == '[' && char == ']');
      if (!matches) continue;
      stack.removeLast();
      if (stack.isEmpty && start != null) {
        ranges.add((start, index + 1));
        start = null;
      }
    }
  }
  if (start != null) ranges.add((start, source.length));
  return ranges;
}

String _applyLineIndent(String value, String source, int start) {
  final lineStart = start == 0 ? 0 : source.lastIndexOf('\n', start - 1) + 1;
  final indent = source.substring(lineStart, start);
  if (indent.trim().isNotEmpty || !value.contains('\n')) return value;
  return value.replaceAll('\n', '\n$indent');
}

JsonIssue _issueFrom(FormatException error, String source) {
  return _issueAtOffset(error.message, source, error.offset ?? 0);
}

JsonIssue _issueAtOffset(String message, String source, int rawOffset) {
  final offset = rawOffset.clamp(0, source.length);
  var line = 1;
  var column = 1;
  for (var index = 0; index < offset; index++) {
    if (source.codeUnitAt(index) == 10) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  return JsonIssue(message: message, line: line, column: column);
}

String _compact(String source) {
  final output = StringBuffer();
  String? quote;
  var escaped = false;
  for (final rune in source.runes) {
    final char = String.fromCharCode(rune);
    if (quote != null) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
    } else if (char == '"' || char == "'") {
      quote = char;
      output.write(char);
    } else if (!_isWhitespace(char)) {
      output.write(char);
    }
  }
  return output.toString();
}

String _prettyPrint(String source, int indentSize) {
  final compact = _compact(source);
  final output = StringBuffer();
  var indent = 0;
  String? quote;
  var escaped = false;
  for (var index = 0; index < compact.length; index++) {
    final char = compact[index];
    if (quote != null) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      output.write(char);
    } else if (char == '{' || char == '[') {
      output.write(char);
      if (!_isEmptyContainer(compact, index)) {
        indent++;
        _writeNewLine(output, indent, indentSize);
      }
    } else if (char == '}' || char == ']') {
      if (index > 0 && !_isOpening(compact[index - 1])) {
        if (indent > 0) indent--;
        _writeNewLine(output, indent, indentSize);
      }
      output.write(char);
    } else if (char == ',') {
      output.write(char);
      _writeNewLine(output, indent, indentSize);
    } else if (char == ':') {
      output.write(': ');
    } else {
      output.write(char);
    }
  }
  return output.toString();
}

bool _isWhitespace(String char) {
  return char == ' ' || char == '\n' || char == '\r' || char == '\t';
}

bool _isEmptyContainer(String source, int index) {
  if (index + 1 >= source.length) return false;
  final current = source[index];
  final next = source[index + 1];
  return (current == '{' && next == '}') || (current == '[' && next == ']');
}

bool _isOpening(String char) => char == '{' || char == '[';

void _writeNewLine(StringBuffer output, int indent, int indentSize) {
  output.write('\n');
  output.write(' ' * (indent * indentSize));
}
