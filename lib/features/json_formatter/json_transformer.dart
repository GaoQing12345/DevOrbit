import 'dart:convert';
import 'dart:isolate';

import 'package:jsonrepair_dart/jsonrepair_dart.dart';

const maxJsonBytes = 10 * 1024 * 1024;

/// Nesting depth accepted by the member sorter. Anything deeper falls back to a
/// plain pretty print instead of risking a stack overflow on hostile input.
const _maxSortDepth = 256;

enum JsonTransformMode { validate, format, compact, sort }

/// How one indentation level is written.
class JsonIndent {
  const JsonIndent({required this.size, required this.tabs});

  const JsonIndent.spaces(int size) : this(size: size, tabs: false);

  final int size;
  final bool tabs;

  String prefix(int depth) => tabs ? '\t' * depth : ' ' * (depth * size);

  @override
  bool operator ==(Object other) =>
      other is JsonIndent && other.size == size && other.tabs == tabs;

  @override
  int get hashCode => Object.hash(size, tabs);
}

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
  const JsonTransformResult.valid(this.output, {this.repaired = false})
    : issue = null;
  const JsonTransformResult.invalid(this.issue, {this.output})
    : repaired = false;

  final String? output;
  final JsonIssue? issue;

  /// Whether the accepted source only became valid after an automatic repair,
  /// so the output no longer matches what the user typed verbatim.
  final bool repaired;
  bool get isValid => issue == null;
}

class JsonTransformer {
  const JsonTransformer();

  Future<JsonTransformResult> run(
    String source,
    JsonTransformMode mode, {
    int indentSize = 2,
    bool useTabs = false,
  }) {
    return Isolate.run(
      () => transformJson(source, mode, indentSize, useTabs: useTabs),
    );
  }

  /// Turns a JSON document into an escaped string literal.
  Future<String> escape(String source) => Isolate.run(() => escapeJson(source));

  /// Reverses [escape], accepting either a full quoted literal or bare text with
  /// backslash escapes such as `{\"a\":1}`.
  Future<String> unescape(String source) =>
      Isolate.run(() => unescapeJson(source));
}

JsonTransformResult transformJson(
  String source,
  JsonTransformMode mode,
  int indentSize, {
  bool useTabs = false,
}) {
  final indent = JsonIndent(size: indentSize, tabs: useTabs);
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
  var transformSource = source;
  var repaired = false;
  try {
    jsonDecode(source);
  } on FormatException catch (strictError) {
    final strictIssue = _issueFrom(strictError, source);
    if (mode == JsonTransformMode.validate) {
      return JsonTransformResult.invalid(strictIssue);
    }
    transformSource = _hasNonJsonTextOutsideContainers(source)
        ? ''
        : _repairJsonDocument(source) ?? '';
    if (transformSource.isEmpty) {
      final partialOutput = _transformJsonContainers(source, mode, indent);
      return JsonTransformResult.invalid(strictIssue, output: partialOutput);
    }
    jsonDecode(transformSource);
    repaired = true;
  }
  // Every JSON value is accepted here, including a bare string, number, `true`
  // and `null`: RFC 8259 treats all of them as complete documents.
  return switch (mode) {
    JsonTransformMode.validate => JsonTransformResult.valid(
      source,
      repaired: repaired,
    ),
    JsonTransformMode.format => JsonTransformResult.valid(
      _prettyPrint(transformSource, indent),
      repaired: repaired,
    ),
    JsonTransformMode.compact => JsonTransformResult.valid(
      _compact(transformSource),
      repaired: repaired,
    ),
    JsonTransformMode.sort => JsonTransformResult.valid(
      _sortMembers(transformSource, indent),
      repaired: repaired,
    ),
  };
}

/// Escapes a document so it can be embedded in source code or a log line.
String escapeJson(String source) => jsonEncode(source);

/// Reverses [escapeJson].
///
/// A single quoted literal is decoded with the JSON grammar so `\u` escapes and
/// surrogate pairs survive; anything else is unescaped in place, which is what
/// a payload copied out of a log usually looks like.
String unescapeJson(String source) {
  final trimmed = source.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is String) return decoded;
    } on FormatException {
      // Fall through to the in-place unescape below.
    }
  }
  return _unescapeInline(source);
}

String _unescapeInline(String source) {
  final output = StringBuffer();
  for (var index = 0; index < source.length; index++) {
    final char = source[index];
    if (char != '\\' || index + 1 >= source.length) {
      output.write(char);
      continue;
    }
    final next = source[index + 1];
    switch (next) {
      case 'n':
        output.write('\n');
        index++;
      case 'r':
        output.write('\r');
        index++;
      case 't':
        output.write('\t');
        index++;
      case 'b':
        output.write('\b');
        index++;
      case 'f':
        output.write('\f');
        index++;
      case '"':
        output.write('"');
        index++;
      case "'":
        output.write("'");
        index++;
      case '/':
        output.write('/');
        index++;
      case '\\':
        output.write('\\');
        index++;
      case 'u':
        final end = index + 6;
        final code = end <= source.length
            ? int.tryParse(source.substring(index + 2, end), radix: 16)
            : null;
        if (code != null) {
          output.writeCharCode(code);
          index += 5;
          break;
        }
        output.write(char);
      default:
        // Unknown escape: keep it untouched so nothing is silently dropped.
        output.write(char);
    }
  }
  return output.toString();
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
  JsonIndent indent,
) {
  if (_looksLikeObjectMembers(source.trim())) {
    final transformed = mode == JsonTransformMode.compact
        ? _compact(source)
        : _prettyPrint(source, indent);
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
        : _prettyPrint(transformSource, indent);
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
  final offset = error.offset ?? 0;
  return _issueAtOffset(
    _localizeMessage(error.message, source, offset),
    source,
    offset,
  );
}

/// Turns the terse English messages of `dart:convert` into a Chinese message
/// that names the actual problem at [rawOffset].
///
/// Dart only ever reports `Unexpected character`, `Unterminated string` and
/// `Unexpected end of input`, so the useful detail has to come from the source
/// itself: the offending character, the one before it and the container the
/// parser was inside.
String _localizeMessage(String raw, String source, int rawOffset) {
  final offset = rawOffset.clamp(0, source.length);
  final structure = _scanStructure(source, offset);
  if (raw == 'Unterminated string') {
    return '字符串没有闭合，缺少结尾的双引号';
  }
  if (raw == 'Unexpected end of input') {
    final missing = structure.missingClosers;
    return missing.isEmpty ? '内容意外结束，JSON 不完整' : '内容意外结束，缺少结尾的 $missing';
  }
  final char = offset < source.length ? source[offset] : '';
  if (char.isEmpty) return '内容意外结束，JSON 不完整';
  final previous = _previousSignificant(source, offset);

  if (structure.atRoot && structure.sawValue) {
    if (previous == '}' || previous == ']') {
      return 'JSON 已经结束，后面还有多余内容';
    }
    if (_isWord(previous) && _isWord(char)) {
      return 'JSON 已经结束，字面量拼写有误或有多余内容';
    }
    return '一个 JSON 文档只能有一个顶层值，这里多了一个值';
  }

  if (structure.expectingKey) {
    if (char == ',') return '这里多了一个逗号，对象里应该写 “键”: 值';
    if ((char == '}' || char == ']') && previous == ',') {
      return '去掉这个多余的逗号，JSON 不允许尾随逗号';
    }
    if (_isWord(char)) return '键名必须用双引号括起来，例如 "$char..."';
    return '此处出现意外字符 “$char”';
  }

  if (char == '+') return '数字不能带 “+” 号';
  if (char == '.' || previous == '.') return '小数点前后必须有数字';
  if (previous == '0' && _isDigit(char)) return '数字不能有前导 0';
  if (char == '\\') return r'转义序列不合法，\u 后面必须跟 4 位十六进制数字';
  if (structure.lastStringWasKey && char != ':') return '键名后面缺少冒号';
  if (previous == ':') return '冒号后面缺少值';
  if (char == ',') return '这里多了一个逗号';
  if (previous == ',') return '逗号后面缺少值';
  if (_endsValue(previous) && _startsValue(char)) return '缺少一个逗号';
  if (_isWord(char)) return 'true / false / null 拼写有误，或字符串缺少引号';
  return '此处出现意外字符 “$char”';
}

bool _isDigit(String char) =>
    char.length == 1 &&
    char.codeUnitAt(0) >= 0x30 &&
    char.codeUnitAt(0) <= 0x39;

bool _isWord(String char) {
  if (char.length != 1) return false;
  final unit = char.codeUnitAt(0);
  return (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      unit > 0x7F;
}

bool _endsValue(String char) =>
    char == '"' || char == '}' || char == ']' || _isWord(char);

bool _startsValue(String char) =>
    char == '"' || char == '{' || char == '[' || _isWord(char);

String _previousSignificant(String source, int offset) {
  for (var index = offset - 1; index >= 0; index--) {
    final char = source[index];
    if (char == ' ' || char == '\n' || char == '\r' || char == '\t') continue;
    return char;
  }
  return '';
}

/// What the parser had seen right before an offset.
class _Structure {
  const _Structure({
    required this.expectingKey,
    required this.sawValue,
    required this.lastStringWasKey,
    required this.missingClosers,
  });

  /// A key is required here, which is true at the start of an object and right
  /// after a member separator.
  final bool expectingKey;

  /// At least one value has already been parsed, so anything after this point
  /// is trailing content.
  final bool sawValue;

  /// The string that ended immediately before the offset was a member key
  /// rather than a value.
  final bool lastStringWasKey;

  /// Closing characters for every container left open, innermost first.
  final String missingClosers;

  /// No container is open, so the parser is at the document root.
  bool get atRoot => missingClosers.isEmpty;
}

/// A JSON-aware walk that stops at [limit] and reports the parser state there.
///
/// The source is usually invalid, so this never rejects input: it tracks
/// brackets, strings and member separators and gives up on anything surprising.
_Structure _scanStructure(String source, int limit) {
  final stack = <_Frame>[];
  var sawValue = false;
  var lastStringWasKey = false;
  var index = 0;

  while (index < limit && index < source.length) {
    final char = source[index];
    if (char == '"') {
      lastStringWasKey = false;
      if (stack.isNotEmpty && stack.last.isObject && stack.last.expectingKey) {
        stack.last.expectingKey = false;
        lastStringWasKey = true;
      }
      index++;
      var escaped = false;
      while (index < source.length) {
        final inner = source[index];
        if (escaped) {
          escaped = false;
        } else if (inner == '\\') {
          escaped = true;
        } else if (inner == '"') {
          index++;
          break;
        }
        index++;
      }
      continue;
    }
    switch (char) {
      case '{':
        stack.add(_Frame(isObject: true));
        index++;
      case '[':
        stack.add(_Frame(isObject: false));
        index++;
      case '}':
      case ']':
        if (stack.isNotEmpty) stack.removeLast();
        sawValue = true;
        index++;
      case ',':
        if (stack.isNotEmpty && stack.last.isObject) {
          stack.last.expectingKey = true;
        }
        index++;
      case ':':
        // The key/colon pair is complete, so a following value is no longer
        // missing its colon.
        lastStringWasKey = false;
        index++;
      case ' ':
      case '\n':
      case '\r':
      case '\t':
        index++;
      default:
        sawValue = true;
        index++;
    }
  }

  final closers = <String>[];
  for (final frame in stack.reversed) {
    closers.add(frame.isObject ? '“}”' : '“]”');
    if (closers.length == 2) break;
  }
  return _Structure(
    expectingKey:
        stack.isNotEmpty && stack.last.isObject && stack.last.expectingKey,
    sawValue: sawValue,
    lastStringWasKey: lastStringWasKey,
    missingClosers: switch (closers.length) {
      0 => '',
      1 => closers.first,
      _ => '${closers[0]} 和 ${closers[1]}',
    },
  );
}

class _Frame {
  _Frame({required this.isObject});

  final bool isObject;
  bool expectingKey = true;
}

JsonIssue _issueAtOffset(String message, String source, int rawOffset) {
  final offset = rawOffset.clamp(0, source.length);
  var line = 1;
  var column = 1;
  var index = 0;
  while (index < offset) {
    final unit = source.codeUnitAt(index);
    if (unit == 0x0A) {
      line++;
      column = 1;
      index++;
      continue;
    }
    // Count code points, not UTF-16 units, so CJK and emoji report the column
    // the user actually sees.
    index += (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < source.length)
        ? 2
        : 1;
    column++;
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

String _prettyPrint(String source, JsonIndent indent) {
  final compact = _compact(source);
  final output = StringBuffer();
  var depth = 0;
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
        depth++;
        _writeNewLine(output, depth, indent);
      }
    } else if (char == '}' || char == ']') {
      if (index > 0 && !_isOpening(compact[index - 1])) {
        if (depth > 0) depth--;
        _writeNewLine(output, depth, indent);
      }
      output.write(char);
    } else if (char == ',') {
      output.write(char);
      _writeNewLine(output, depth, indent);
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

void _writeNewLine(StringBuffer output, int depth, JsonIndent indent) {
  output.write('\n');
  output.write(indent.prefix(depth));
}

/// Sorts every object's members by key while keeping each literal exactly as
/// written.
///
/// Going through `jsonDecode`/`jsonEncode` would rewrite numbers (`1e5`) and
/// silently drop duplicate keys, so the document is re-emitted from its own
/// token spans instead.
String _sortMembers(String source, JsonIndent indent) {
  final _Node root;
  try {
    root = _NodeParser(source).parse();
  } on FormatException {
    return _prettyPrint(source, indent);
  } on StateError {
    return _prettyPrint(source, indent);
  }
  final output = StringBuffer();
  _emitNode(root, output, indent, 0);
  return output.toString();
}

sealed class _Node {
  const _Node();
}

class _ObjectNode extends _Node {
  const _ObjectNode(this.members);

  final List<_Member> members;
}

class _ArrayNode extends _Node {
  const _ArrayNode(this.elements);

  final List<_Node> elements;
}

class _LiteralNode extends _Node {
  const _LiteralNode(this.raw);

  final String raw;
}

class _Member {
  const _Member({
    required this.key,
    required this.compareKey,
    required this.value,
  });

  /// The key exactly as it appeared, quotes included.
  final String key;

  /// The decoded key text, used for ordering.
  final String compareKey;

  final _Node value;
}

void _emitNode(_Node node, StringBuffer output, JsonIndent indent, int depth) {
  switch (node) {
    case _LiteralNode(:final raw):
      output.write(raw);
    case _ArrayNode(:final elements):
      if (elements.isEmpty) {
        output.write('[]');
        return;
      }
      output.write('[\n');
      for (var index = 0; index < elements.length; index++) {
        output.write(indent.prefix(depth + 1));
        _emitNode(elements[index], output, indent, depth + 1);
        if (index < elements.length - 1) output.write(',');
        output.write('\n');
      }
      output.write(indent.prefix(depth));
      output.write(']');
    case _ObjectNode(:final members):
      if (members.isEmpty) {
        output.write('{}');
        return;
      }
      output.write('{\n');
      for (var index = 0; index < members.length; index++) {
        output.write(indent.prefix(depth + 1));
        output.write(members[index].key);
        output.write(': ');
        _emitNode(members[index].value, output, indent, depth + 1);
        if (index < members.length - 1) output.write(',');
        output.write('\n');
      }
      output.write(indent.prefix(depth));
      output.write('}');
  }
}

class _NodeParser {
  _NodeParser(this.source);

  final String source;
  int _index = 0;
  int _depth = 0;

  _Node parse() {
    final node = _parseValue();
    _skipWhitespace();
    if (_index < source.length) {
      throw const FormatException('trailing content');
    }
    return node;
  }

  _Node _parseValue() {
    if (_depth > _maxSortDepth) throw const FormatException('too deep');
    _skipWhitespace();
    final char = _peek();
    switch (char) {
      case '{':
        return _parseObject();
      case '[':
        return _parseArray();
      case null:
        throw const FormatException('unexpected end');
      default:
        return _LiteralNode(_parseLiteral());
    }
  }

  _Node _parseObject() {
    _depth++;
    _expect('{');
    final members = <_Member>[];
    _skipWhitespace();
    if (_peek() == '}') {
      _index++;
      _depth--;
      return const _ObjectNode([]);
    }
    while (true) {
      _skipWhitespace();
      final key = _parseString();
      _skipWhitespace();
      _expect(':');
      final value = _parseValue();
      members.add(_Member(key: key, compareKey: _decodeKey(key), value: value));
      _skipWhitespace();
      final char = _peek();
      if (char == ',') {
        _index++;
        continue;
      }
      if (char == '}') {
        _index++;
        break;
      }
      throw const FormatException('expected , or }');
    }
    _depth--;
    return _ObjectNode(_sorted(members));
  }

  _Node _parseArray() {
    _depth++;
    _expect('[');
    final elements = <_Node>[];
    _skipWhitespace();
    if (_peek() == ']') {
      _index++;
      _depth--;
      return const _ArrayNode([]);
    }
    while (true) {
      elements.add(_parseValue());
      _skipWhitespace();
      final char = _peek();
      if (char == ',') {
        _index++;
        continue;
      }
      if (char == ']') {
        _index++;
        break;
      }
      throw const FormatException('expected , or ]');
    }
    _depth--;
    return _ArrayNode(elements);
  }

  /// Code point order on the decoded key, with duplicates kept in place.
  List<_Member> _sorted(List<_Member> members) {
    final indexed = [
      for (var index = 0; index < members.length; index++)
        (index: index, member: members[index]),
    ];
    indexed.sort((left, right) {
      final compared = left.member.compareKey.compareTo(
        right.member.compareKey,
      );
      return compared != 0 ? compared : left.index.compareTo(right.index);
    });
    return [for (final entry in indexed) entry.member];
  }

  String _parseString() {
    if (_peek() != '"') throw const FormatException('expected string');
    final start = _index;
    _index++;
    var escaped = false;
    while (_index < source.length) {
      final char = source[_index];
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        _index++;
        return source.substring(start, _index);
      }
      _index++;
    }
    throw const FormatException('unterminated string');
  }

  String _parseLiteral() {
    final start = _index;
    while (_index < source.length) {
      final char = source[_index];
      if (char == ',' ||
          char == '}' ||
          char == ']' ||
          char == ' ' ||
          char == '\n' ||
          char == '\r' ||
          char == '\t') {
        break;
      }
      _index++;
    }
    if (_index == start) throw const FormatException('empty literal');
    return source.substring(start, _index);
  }

  String _decodeKey(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String) return decoded;
    } on FormatException {
      // Fall back to the raw text; ordering stays deterministic either way.
    }
    return raw;
  }

  void _skipWhitespace() {
    while (_index < source.length) {
      final char = source[_index];
      if (char == ' ' || char == '\n' || char == '\r' || char == '\t') {
        _index++;
        continue;
      }
      return;
    }
  }

  String? _peek() => _index < source.length ? source[_index] : null;

  void _expect(String char) {
    if (_peek() != char) throw FormatException('expected $char');
    _index++;
  }
}
