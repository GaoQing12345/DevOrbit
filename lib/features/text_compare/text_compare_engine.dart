import 'package:characters/characters.dart';
import 'package:diffutil_dart/diffutil.dart';

import 'text_compare_models.dart';

/// Line oriented diff with the knobs the desktop comparers expose.
///
/// The pipeline is:
/// 1. normalise line breaks and split both sides into lines,
/// 2. mark the lines the active rules say to skip (blank lines, the empty line
///    produced by a final newline),
/// 3. find the unchanged anchors with a list diff,
/// 4. inside each change block pair left and right lines by similarity instead
///    of blindly by position, so one inserted line no longer turns the whole
///    block into edits,
/// 5. highlight the changed words of a paired line, trimming the shared prefix
///    and suffix on grapheme boundaries.
class TextCompareEngine {
  const TextCompareEngine();

  /// Above this many line pairs a block falls back to positional pairing so a
  /// pathological file cannot stall the comparison isolate.
  static const int _maxAlignmentCells = 40000;

  /// Minimum similarity for two lines to be reported as one modified line
  /// instead of a removal plus an addition.
  static const double _pairSimilarity = 0.4;

  /// Fragmented highlights covering this share of the longest line collapse
  /// into one block, which is how the mature tools avoid confetti.
  static const double _collapseShare = 0.7;

  static final RegExp _leadingWhitespace = RegExp(r'^\s+');
  static final RegExp _trailingWhitespace = RegExp(r'\s+$');
  static final RegExp _anyWhitespace = RegExp(r'\s+');

  /// Whitespace, then a single ideograph (so CJK text stays per character),
  /// then a word, then a punctuation run.
  static final RegExp _tokenPattern = RegExp(
    r'\s+'
    r'|[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\uAC00-\uD7AF]'
    r'|[\p{L}\p{N}_]+'
    r'|[^\s\p{L}\p{N}_]+',
    unicode: true,
  );

  TextDiffResult compare({
    required String left,
    required String right,
    required TextCompareOptions options,
  }) {
    final leftText = _normalizeLineBreaks(left);
    final rightText = _normalizeLineBreaks(right);
    final leftLines = _splitLines(leftText);
    final rightLines = _splitLines(rightText);
    final leftSkipped = _skippedLines(leftLines, leftText, options);
    final rightSkipped = _skippedLines(rightLines, rightText, options);
    final anchors = _findAnchors(
      _tokens(leftLines, options, fromLeft: true),
      _tokens(rightLines, options, fromLeft: false),
    );
    final leftResult = List<TextDiffLine>.generate(
      leftLines.length,
      (index) => TextDiffLine(
        lineNumber: index + 1,
        status: TextDiffLineStatus.unchanged,
      ),
      growable: false,
    );
    final rightResult = List<TextDiffLine>.generate(
      rightLines.length,
      (index) => TextDiffLine(
        lineNumber: index + 1,
        status: TextDiffLineStatus.unchanged,
      ),
      growable: false,
    );

    final hunks = <TextDiffHunk>[];
    var addedCount = 0;
    var removedCount = 0;
    var modifiedCount = 0;
    var previousLeft = -1;
    var previousRight = -1;
    for (final anchor in [
      ...anchors,
      (leftIndex: leftLines.length, rightIndex: rightLines.length),
    ]) {
      final deleted = _selectable(
        previousLeft + 1,
        anchor.leftIndex,
        leftSkipped,
      );
      final inserted = _selectable(
        previousRight + 1,
        anchor.rightIndex,
        rightSkipped,
      );
      var hunkAdded = 0;
      var hunkRemoved = 0;
      var hunkModified = 0;
      int? hunkLeft;
      int? hunkRight;
      for (final pair in _alignLines(
        leftLines: leftLines,
        rightLines: rightLines,
        deleted: deleted,
        inserted: inserted,
        options: options,
      )) {
        if (pair.rightIndex < 0) {
          leftResult[pair.leftIndex] = TextDiffLine(
            lineNumber: pair.leftIndex + 1,
            status: TextDiffLineStatus.removed,
          );
          removedCount++;
          hunkRemoved++;
          hunkLeft ??= pair.leftIndex;
          hunkRight ??= previousRight + 1;
          continue;
        }
        if (pair.leftIndex < 0) {
          rightResult[pair.rightIndex] = TextDiffLine(
            lineNumber: pair.rightIndex + 1,
            status: TextDiffLineStatus.added,
          );
          addedCount++;
          hunkAdded++;
          hunkLeft ??= previousLeft + 1;
          hunkRight ??= pair.rightIndex;
          continue;
        }
        final ranges = _intraLineRanges(
          leftLines[pair.leftIndex],
          rightLines[pair.rightIndex],
          options,
        );
        if (ranges.left.isEmpty && ranges.right.isEmpty) {
          // The rules consider these two lines identical; do not report an
          // edit that the toolbar claims to ignore.
          continue;
        }
        leftResult[pair.leftIndex] = TextDiffLine(
          lineNumber: pair.leftIndex + 1,
          status: TextDiffLineStatus.modified,
          ranges: ranges.left,
        );
        rightResult[pair.rightIndex] = TextDiffLine(
          lineNumber: pair.rightIndex + 1,
          status: TextDiffLineStatus.modified,
          ranges: ranges.right,
        );
        modifiedCount++;
        hunkModified++;
        hunkLeft ??= pair.leftIndex;
        hunkRight ??= pair.rightIndex;
      }
      if (hunkLeft != null && hunkRight != null) {
        hunks.add(
          TextDiffHunk(
            leftIndex: hunkLeft,
            rightIndex: hunkRight,
            added: hunkAdded,
            removed: hunkRemoved,
            modified: hunkModified,
          ),
        );
      }
      previousLeft = anchor.leftIndex;
      previousRight = anchor.rightIndex;
    }

    return TextDiffResult(
      leftLines: leftResult,
      rightLines: rightResult,
      addedCount: addedCount,
      removedCount: removedCount,
      modifiedCount: modifiedCount,
      hunks: hunks,
    );
  }

  List<({int leftIndex, int rightIndex})> _findAnchors(
    List<_IndexedToken> left,
    List<_IndexedToken> right,
  ) {
    final current = List<_IndexedToken>.of(left);
    final diff = calculateListDiff<_IndexedToken>(
      left,
      right,
      detectMoves: false,
      equalityChecker: (a, b) => a.normalized == b.normalized,
    );
    for (final update in diff.getUpdatesWithData()) {
      update.when(
        insert: (position, data) => current.insert(position, data),
        remove: (position, data) => current.removeAt(position),
        change: (_, _, _) {},
        move: (_, _, _) {},
      );
    }
    return [
      for (var rightIndex = 0; rightIndex < current.length; rightIndex++)
        if (current[rightIndex].fromLeft)
          (leftIndex: current[rightIndex].index, rightIndex: rightIndex),
    ];
  }

  /// Aligns the deleted and inserted lines of one change block.
  ///
  /// Returns one record per line: both indices set for a rewrite, only
  /// `rightIndex` for an insertion, only `leftIndex` for a removal.
  List<({int leftIndex, int rightIndex})> _alignLines({
    required List<String> leftLines,
    required List<String> rightLines,
    required List<int> deleted,
    required List<int> inserted,
    required TextCompareOptions options,
  }) {
    if (deleted.isEmpty && inserted.isEmpty) return const [];
    if (deleted.isEmpty) {
      return [for (final index in inserted) (leftIndex: -1, rightIndex: index)];
    }
    if (inserted.isEmpty) {
      return [for (final index in deleted) (leftIndex: index, rightIndex: -1)];
    }
    final leftKeys = [
      for (final index in deleted) _normalizeLine(leftLines[index], options),
    ];
    final rightKeys = [
      for (final index in inserted) _normalizeLine(rightLines[index], options),
    ];
    // A block with the same number of lines on both sides is a rewrite, and
    // every comparer pairs it position by position; only a block with a
    // different line count needs the similarity search to find where the
    // insertion actually sits.
    if (deleted.length == inserted.length ||
        deleted.length * inserted.length > _maxAlignmentCells) {
      return _positionalAlignment(deleted, inserted);
    }
    return _similarityAlignment(deleted, inserted, leftKeys, rightKeys);
  }

  List<({int leftIndex, int rightIndex})> _positionalAlignment(
    List<int> deleted,
    List<int> inserted,
  ) {
    final shared = deleted.length < inserted.length
        ? deleted.length
        : inserted.length;
    return [
      for (var index = 0; index < shared; index++)
        (leftIndex: deleted[index], rightIndex: inserted[index]),
      for (var index = shared; index < deleted.length; index++)
        (leftIndex: deleted[index], rightIndex: -1),
      for (var index = shared; index < inserted.length; index++)
        (leftIndex: -1, rightIndex: inserted[index]),
    ];
  }

  /// Weighted sequence alignment: pairing two lines only pays off above
  /// [_pairSimilarity], so a dissimilar neighbour is reported as an insertion
  /// (or a removal) instead of dragging the rest of the block along.
  List<({int leftIndex, int rightIndex})> _similarityAlignment(
    List<int> deleted,
    List<int> inserted,
    List<String> leftKeys,
    List<String> rightKeys,
  ) {
    final rows = leftKeys.length;
    final columns = rightKeys.length;
    final similarity = List<List<double>>.generate(
      rows,
      (row) => List<double>.generate(
        columns,
        (column) => _similarity(leftKeys[row], rightKeys[column]),
      ),
      growable: false,
    );
    final score = List<List<double>>.generate(
      rows + 1,
      (_) => List<double>.filled(columns + 1, 0),
      growable: false,
    );
    for (var row = 1; row <= rows; row++) {
      for (var column = 1; column <= columns; column++) {
        final above = score[row - 1][column];
        final before = score[row][column - 1];
        var best = above > before ? above : before;
        final value = similarity[row - 1][column - 1];
        if (value > _pairSimilarity) {
          final paired = score[row - 1][column - 1] + value;
          if (paired > best) best = paired;
        }
        score[row][column] = best;
      }
    }

    final alignment = <({int leftIndex, int rightIndex})>[];
    var row = rows;
    var column = columns;
    while (row > 0 || column > 0) {
      if (row > 0 && column > 0) {
        final value = similarity[row - 1][column - 1];
        if (value > _pairSimilarity &&
            (score[row][column] - (score[row - 1][column - 1] + value)).abs() <
                1e-9) {
          alignment.add((
            leftIndex: deleted[row - 1],
            rightIndex: inserted[column - 1],
          ));
          row--;
          column--;
          continue;
        }
      }
      if (row > 0 &&
          (column == 0 ||
              (score[row][column] - score[row - 1][column]).abs() < 1e-9)) {
        alignment.add((leftIndex: deleted[row - 1], rightIndex: -1));
        row--;
        continue;
      }
      alignment.add((leftIndex: -1, rightIndex: inserted[column - 1]));
      column--;
    }
    return alignment.reversed.toList(growable: false);
  }

  ({List<TextDiffRange> left, List<TextDiffRange> right}) _intraLineRanges(
    String left,
    String right,
    TextCompareOptions options,
  ) {
    if (left == right) return (left: const [], right: const []);
    final leftTokens = _wordTokens(left);
    final rightTokens = _wordTokens(right);
    final leftChanged = <_Token>[];
    final rightChanged = <_Token>[];
    final diff = calculateListDiff<_Token>(
      leftTokens,
      rightTokens,
      detectMoves: false,
      equalityChecker: (a, b) =>
          _tokenKey(left, a, options) == _tokenKey(right, b, options),
    );
    for (final update in diff.getUpdatesWithData()) {
      update.when(
        insert: (_, data) {
          if (_tokenKey(right, data, options).isNotEmpty) {
            rightChanged.add(data);
          }
        },
        remove: (_, data) {
          if (_tokenKey(left, data, options).isNotEmpty) {
            leftChanged.add(data);
          }
        },
        change: (_, previous, next) {
          if (_tokenKey(left, previous, options).isNotEmpty) {
            leftChanged.add(previous);
          }
          if (_tokenKey(right, next, options).isNotEmpty) {
            rightChanged.add(next);
          }
        },
        move: (_, _, _) {},
      );
    }
    leftChanged.sort((a, b) => a.start.compareTo(b.start));
    rightChanged.sort((a, b) => a.start.compareTo(b.start));

    final leftRanges = <TextDiffRange>[];
    final rightRanges = <TextDiffRange>[];
    final shared = leftChanged.length < rightChanged.length
        ? leftChanged.length
        : rightChanged.length;
    for (var index = 0; index < shared; index++) {
      _refineToken(
        left,
        leftChanged[index],
        right,
        rightChanged[index],
        leftRanges,
        rightRanges,
      );
    }
    for (var index = shared; index < leftChanged.length; index++) {
      leftRanges.add(
        TextDiffRange(
          start: leftChanged[index].start,
          end: leftChanged[index].end,
        ),
      );
    }
    for (var index = shared; index < rightChanged.length; index++) {
      rightRanges.add(
        TextDiffRange(
          start: rightChanged[index].start,
          end: rightChanged[index].end,
        ),
      );
    }
    return (
      left: _mergeRanges(leftRanges, left.length, right.length),
      right: _mergeRanges(rightRanges, right.length, left.length),
    );
  }

  /// Keeps the shared prefix and suffix out of the highlight so only the real
  /// edit is painted, walking graphemes so a surrogate pair is never split.
  void _refineToken(
    String left,
    _Token leftToken,
    String right,
    _Token rightToken,
    List<TextDiffRange> leftRanges,
    List<TextDiffRange> rightRanges,
  ) {
    final leftValue = left.substring(leftToken.start, leftToken.end);
    final rightValue = right.substring(rightToken.start, rightToken.end);
    if (leftValue == rightValue) return;
    final leftGraphemes = leftValue.characters.toList(growable: false);
    final rightGraphemes = rightValue.characters.toList(growable: false);
    final shortest = leftGraphemes.length < rightGraphemes.length
        ? leftGraphemes.length
        : rightGraphemes.length;
    var prefix = 0;
    while (prefix < shortest &&
        leftGraphemes[prefix] == rightGraphemes[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        leftGraphemes[leftGraphemes.length - 1 - suffix] ==
            rightGraphemes[rightGraphemes.length - 1 - suffix]) {
      suffix++;
    }
    final leftStart = leftToken.start + _graphemeOffset(leftGraphemes, prefix);
    final leftEnd =
        leftToken.start +
        _graphemeOffset(leftGraphemes, leftGraphemes.length - suffix);
    final rightStart =
        rightToken.start + _graphemeOffset(rightGraphemes, prefix);
    final rightEnd =
        rightToken.start +
        _graphemeOffset(rightGraphemes, rightGraphemes.length - suffix);
    if (leftEnd > leftStart) {
      leftRanges.add(TextDiffRange(start: leftStart, end: leftEnd));
    }
    if (rightEnd > rightStart) {
      rightRanges.add(TextDiffRange(start: rightStart, end: rightEnd));
    }
  }

  List<TextDiffRange> _mergeRanges(
    List<TextDiffRange> ranges,
    int lineLength,
    int otherLength,
  ) {
    if (ranges.isEmpty) return const [];
    final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <TextDiffRange>[];
    for (final range in sorted) {
      if (range.end <= range.start) continue;
      if (merged.isNotEmpty && range.start <= merged.last.end) {
        final previous = merged.removeLast();
        merged.add(
          TextDiffRange(
            start: previous.start,
            end: range.end > previous.end ? range.end : previous.end,
          ),
        );
      } else {
        merged.add(range);
      }
    }
    if (merged.length < 3) return merged;
    final longest = lineLength > otherLength ? lineLength : otherLength;
    if (longest == 0) return merged;
    var covered = 0;
    for (final range in merged) {
      covered += range.end - range.start;
    }
    if (covered < longest * _collapseShare) return merged;
    return [TextDiffRange(start: merged.first.start, end: merged.last.end)];
  }

  List<_Token> _wordTokens(String text) => [
    for (final match in _tokenPattern.allMatches(text))
      _Token(start: match.start, end: match.end),
  ];

  /// Key used to decide whether two tokens of a line are the same.
  ///
  /// Whitespace tokens the active rules ignore collapse to an empty key, and
  /// empty keys are dropped from the highlight entirely, so choosing "ignore
  /// leading whitespace" really hides the indentation instead of painting it.
  String _tokenKey(String line, _Token token, TextCompareOptions options) {
    final value = line.substring(token.start, token.end);
    if (value.trim().isNotEmpty) {
      return options.ignoreCase ? value.toLowerCase() : value;
    }
    if (options.ignoreAllWhitespace) return '';
    if (token.start == 0 && options.ignoreLeadingWhitespace) return '';
    if (token.end == line.length && options.ignoreTrailingWhitespace) return '';
    return value;
  }

  double _similarity(String left, String right) {
    if (left == right) return 1;
    if (left.isEmpty || right.isEmpty) return 0;
    if (left.length < 3 || right.length < 3) {
      return _dice(_unigrams(left), _unigrams(right));
    }
    return _dice(_bigrams(left), _bigrams(right));
  }

  Map<int, int> _bigrams(String value) {
    final counts = <int, int>{};
    for (var index = 0; index + 1 < value.length; index++) {
      final key = value.codeUnitAt(index) * 65536 + value.codeUnitAt(index + 1);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  Map<int, int> _unigrams(String value) {
    final counts = <int, int>{};
    for (var index = 0; index < value.length; index++) {
      final key = value.codeUnitAt(index);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// Sorensen-Dice coefficient over the multiset of n-grams.
  double _dice(Map<int, int> left, Map<int, int> right) {
    var common = 0;
    var total = 0;
    for (final entry in left.entries) {
      total += entry.value;
      final other = right[entry.key];
      if (other != null) common += entry.value < other ? entry.value : other;
    }
    for (final value in right.values) {
      total += value;
    }
    return total == 0 ? 0 : 2 * common / total;
  }

  String _normalizeLine(String value, TextCompareOptions options) {
    var normalized = value;
    if (options.ignoreAllWhitespace) {
      normalized = normalized.replaceAll(_anyWhitespace, '');
    } else {
      if (options.ignoreLeadingWhitespace) {
        normalized = normalized.replaceFirst(_leadingWhitespace, '');
      }
      if (options.ignoreTrailingWhitespace) {
        normalized = normalized.replaceFirst(_trailingWhitespace, '');
      }
    }
    if (options.ignoreCase) normalized = normalized.toLowerCase();
    return normalized;
  }

  /// Lines the active rules keep out of the comparison. They stay in the result
  /// list (so line numbers keep matching the editors) but never become a hunk.
  List<bool> _skippedLines(
    List<String> lines,
    String text,
    TextCompareOptions options,
  ) {
    final skipped = List<bool>.filled(lines.length, false);
    if (options.ignoreBlankLines) {
      for (var index = 0; index < lines.length; index++) {
        if (lines[index].trim().isEmpty) skipped[index] = true;
      }
    }
    if (options.ignoreTrailingNewline &&
        lines.isNotEmpty &&
        text.endsWith('\n')) {
      skipped[lines.length - 1] = true;
    }
    return skipped;
  }

  List<int> _selectable(int start, int end, List<bool> skipped) {
    final indices = <int>[];
    for (var index = start; index < end; index++) {
      if (!skipped[index]) indices.add(index);
    }
    return indices;
  }

  List<_IndexedToken> _tokens(
    List<String> lines,
    TextCompareOptions options, {
    required bool fromLeft,
  }) => [
    for (var index = 0; index < lines.length; index++)
      _IndexedToken(
        index: index,
        normalized: _normalizeLine(lines[index], options),
        fromLeft: fromLeft,
      ),
  ];

  String _normalizeLineBreaks(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  List<String> _splitLines(String text) =>
      text.isEmpty ? const [] : text.split('\n');

  int _graphemeOffset(List<String> graphemes, int count) {
    var offset = 0;
    for (var index = 0; index < count; index++) {
      offset += graphemes[index].length;
    }
    return offset;
  }
}

class _IndexedToken {
  const _IndexedToken({
    required this.index,
    required this.normalized,
    required this.fromLeft,
  });

  final int index;
  final String normalized;
  final bool fromLeft;
}

class _Token {
  const _Token({required this.start, required this.end});

  final int start;
  final int end;
}
