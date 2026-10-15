enum TextCompareSide { left, right }

enum TextCompareStatus { idle, comparing, unchanged, changed, stale, error }

enum TextDiffLineStatus { unchanged, added, removed, modified }

/// Comparison rules shared by the engine, the toolbar and the copied summary.
///
/// The flags mirror what mature desktop comparers expose (Beyond Compare,
/// WinMerge, Meld, `diff -w -b -B -Z`): per line whitespace handling, blank
/// line skipping and a trailing newline rule. Every flag is independent so a
/// caller can pick exactly the behaviour it needs.
class TextCompareOptions {
  const TextCompareOptions({
    this.ignoreCase = false,
    this.ignoreLeadingWhitespace = false,
    this.ignoreTrailingWhitespace = false,
    this.ignoreAllWhitespace = false,
    this.ignoreBlankLines = false,
    this.ignoreTrailingNewline = false,
  });

  /// Compares `Hello` and `hello` as equal.
  final bool ignoreCase;

  /// Drops the indentation in front of every line, not just the first one.
  final bool ignoreLeadingWhitespace;

  /// Drops the spaces and tabs at the end of every line.
  final bool ignoreTrailingWhitespace;

  /// Drops every whitespace character, including runs inside a line. Wins over
  /// [ignoreLeadingWhitespace] and [ignoreTrailingWhitespace].
  final bool ignoreAllWhitespace;

  /// Skips blank or whitespace-only lines on both sides.
  final bool ignoreBlankLines;

  /// Treats a missing newline at the end of the text as equal, so `a\n` and
  /// `a` compare as identical.
  final bool ignoreTrailingNewline;

  bool get ignoresWhitespace =>
      ignoreAllWhitespace ||
      ignoreLeadingWhitespace ||
      ignoreTrailingWhitespace;

  bool get isExact =>
      !ignoreCase &&
      !ignoresWhitespace &&
      !ignoreBlankLines &&
      !ignoreTrailingNewline;

  /// Human readable rules, used by the copied report and the status bar.
  List<String> get ruleLabels => [
    if (ignoreCase) '忽略大小写',
    if (ignoreLeadingWhitespace) '忽略行首空白',
    if (ignoreTrailingWhitespace) '忽略行尾空白',
    if (ignoreAllWhitespace) '忽略所有空白',
    if (ignoreBlankLines) '忽略空行',
    if (ignoreTrailingNewline) '忽略末尾换行',
  ];

  TextCompareOptions copyWith({
    bool? ignoreCase,
    bool? ignoreLeadingWhitespace,
    bool? ignoreTrailingWhitespace,
    bool? ignoreAllWhitespace,
    bool? ignoreBlankLines,
    bool? ignoreTrailingNewline,
  }) {
    return TextCompareOptions(
      ignoreCase: ignoreCase ?? this.ignoreCase,
      ignoreLeadingWhitespace:
          ignoreLeadingWhitespace ?? this.ignoreLeadingWhitespace,
      ignoreTrailingWhitespace:
          ignoreTrailingWhitespace ?? this.ignoreTrailingWhitespace,
      ignoreAllWhitespace: ignoreAllWhitespace ?? this.ignoreAllWhitespace,
      ignoreBlankLines: ignoreBlankLines ?? this.ignoreBlankLines,
      ignoreTrailingNewline:
          ignoreTrailingNewline ?? this.ignoreTrailingNewline,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TextCompareOptions &&
        other.ignoreCase == ignoreCase &&
        other.ignoreLeadingWhitespace == ignoreLeadingWhitespace &&
        other.ignoreTrailingWhitespace == ignoreTrailingWhitespace &&
        other.ignoreAllWhitespace == ignoreAllWhitespace &&
        other.ignoreBlankLines == ignoreBlankLines &&
        other.ignoreTrailingNewline == ignoreTrailingNewline;
  }

  @override
  int get hashCode => Object.hash(
    ignoreCase,
    ignoreLeadingWhitespace,
    ignoreTrailingWhitespace,
    ignoreAllWhitespace,
    ignoreBlankLines,
    ignoreTrailingNewline,
  );
}

class TextDiffRange {
  const TextDiffRange({required this.start, required this.end});

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is TextDiffRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextDiffRange($start, $end)';
}

class TextDiffLine {
  const TextDiffLine({
    required this.lineNumber,
    required this.status,
    this.ranges = const [],
  });

  final int lineNumber;
  final TextDiffLineStatus status;
  final List<TextDiffRange> ranges;
}

/// One contiguous change block. Used to jump between differences the way
/// `F7`/`Shift+F7` do in the popular comparers.
class TextDiffHunk {
  const TextDiffHunk({
    required this.leftIndex,
    required this.rightIndex,
    this.added = 0,
    this.removed = 0,
    this.modified = 0,
  });

  /// First affected line on the left. Equals the number of left lines when the
  /// block only appends at the end of the text.
  final int leftIndex;

  /// First affected line on the right, with the same semantics.
  final int rightIndex;

  final int added;
  final int removed;
  final int modified;

  int get changeCount => added + removed + modified;
}

class TextDiffResult {
  const TextDiffResult({
    required this.leftLines,
    required this.rightLines,
    required this.addedCount,
    required this.removedCount,
    required this.modifiedCount,
    this.hunks = const [],
  });

  final List<TextDiffLine> leftLines;
  final List<TextDiffLine> rightLines;
  final int addedCount;
  final int removedCount;
  final int modifiedCount;
  final List<TextDiffHunk> hunks;

  bool get hasChanges =>
      addedCount > 0 || removedCount > 0 || modifiedCount > 0;
}
