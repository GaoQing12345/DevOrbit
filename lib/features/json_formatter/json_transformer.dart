import 'dart:convert';
import 'dart:isolate';

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
  const JsonTransformResult.invalid(this.issue) : output = null;

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
  try {
    jsonDecode(source);
  } on FormatException catch (error) {
    return JsonTransformResult.invalid(_issueFrom(error, source));
  }
  return switch (mode) {
    JsonTransformMode.validate => JsonTransformResult.valid(source),
    JsonTransformMode.format => JsonTransformResult.valid(
      _prettyPrint(source, indentSize),
    ),
    JsonTransformMode.compact => JsonTransformResult.valid(_compact(source)),
  };
}

JsonIssue _issueFrom(FormatException error, String source) {
  final offset = (error.offset ?? 0).clamp(0, source.length);
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
  return JsonIssue(message: error.message, line: line, column: column);
}

String _compact(String source) {
  final output = StringBuffer();
  var inString = false;
  var escaped = false;
  for (final rune in source.runes) {
    final char = String.fromCharCode(rune);
    if (inString) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
    } else if (char == '"') {
      inString = true;
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
  var inString = false;
  var escaped = false;
  for (var index = 0; index < compact.length; index++) {
    final char = compact[index];
    if (inString) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      output.write(char);
    } else if (char == '{' || char == '[') {
      output.write(char);
      if (!_isEmptyContainer(compact, index)) {
        indent++;
        _writeNewLine(output, indent, indentSize);
      }
    } else if (char == '}' || char == ']') {
      if (index > 0 && !_isOpening(compact[index - 1])) {
        indent--;
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
