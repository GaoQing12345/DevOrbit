enum TextCompareSide { left, right }

enum TextCompareStatus { idle, comparing, unchanged, changed, stale, error }

enum TextDiffLineStatus { unchanged, added, removed, modified }

class TextCompareOptions {
  const TextCompareOptions({
    this.ignoreCase = false,
    this.ignoreTrailingWhitespace = false,
  });

  final bool ignoreCase;
  final bool ignoreTrailingWhitespace;

  TextCompareOptions copyWith({
    bool? ignoreCase,
    bool? ignoreTrailingWhitespace,
  }) {
    return TextCompareOptions(
      ignoreCase: ignoreCase ?? this.ignoreCase,
      ignoreTrailingWhitespace:
          ignoreTrailingWhitespace ?? this.ignoreTrailingWhitespace,
    );
  }
}

class TextDiffRange {
  const TextDiffRange({required this.start, required this.end});

  final int start;
  final int end;
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

class TextDiffResult {
  const TextDiffResult({
    required this.leftLines,
    required this.rightLines,
    required this.addedCount,
    required this.removedCount,
    required this.modifiedCount,
  });

  final List<TextDiffLine> leftLines;
  final List<TextDiffLine> rightLines;
  final int addedCount;
  final int removedCount;
  final int modifiedCount;

  bool get hasChanges =>
      addedCount > 0 || removedCount > 0 || modifiedCount > 0;
}
