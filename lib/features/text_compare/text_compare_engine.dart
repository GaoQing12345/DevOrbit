import 'package:characters/characters.dart';
import 'package:diffutil_dart/diffutil.dart';

import 'text_compare_models.dart';

class TextCompareEngine {
  const TextCompareEngine();

  TextDiffResult compare({
    required String left,
    required String right,
    required TextCompareOptions options,
  }) {
    final leftLines = _splitLines(left);
    final rightLines = _splitLines(right);
    final leftTokens = [
      for (var index = 0; index < leftLines.length; index++)
        _IndexedToken(
          index: index,
          normalized: _normalize(leftLines[index], options),
          fromOldList: true,
        ),
    ];
    final rightTokens = [
      for (var index = 0; index < rightLines.length; index++)
        _IndexedToken(
          index: index,
          normalized: _normalize(rightLines[index], options),
          fromOldList: false,
        ),
    ];
    final anchors = _findAnchors(leftTokens, rightTokens);
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

    var previousLeft = -1;
    var previousRight = -1;
    var addedCount = 0;
    var removedCount = 0;
    var modifiedCount = 0;
    for (final anchor in [
      ...anchors,
      (leftIndex: leftLines.length, rightIndex: rightLines.length),
    ]) {
      final deletedStart = previousLeft + 1;
      final deletedCount = anchor.leftIndex - deletedStart;
      final addedStart = previousRight + 1;
      final addedInHunk = anchor.rightIndex - addedStart;
      final pairedCount = deletedCount < addedInHunk
          ? deletedCount
          : addedInHunk;

      for (var offset = 0; offset < pairedCount; offset++) {
        final leftIndex = deletedStart + offset;
        final rightIndex = addedStart + offset;
        final ranges = _characterRanges(
          leftLines[leftIndex],
          rightLines[rightIndex],
        );
        leftResult[leftIndex] = TextDiffLine(
          lineNumber: leftIndex + 1,
          status: TextDiffLineStatus.modified,
          ranges: ranges.left,
        );
        rightResult[rightIndex] = TextDiffLine(
          lineNumber: rightIndex + 1,
          status: TextDiffLineStatus.modified,
          ranges: ranges.right,
        );
        modifiedCount++;
      }
      for (var offset = pairedCount; offset < deletedCount; offset++) {
        final index = deletedStart + offset;
        leftResult[index] = TextDiffLine(
          lineNumber: index + 1,
          status: TextDiffLineStatus.removed,
        );
        removedCount++;
      }
      for (var offset = pairedCount; offset < addedInHunk; offset++) {
        final index = addedStart + offset;
        rightResult[index] = TextDiffLine(
          lineNumber: index + 1,
          status: TextDiffLineStatus.added,
        );
        addedCount++;
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
        if (current[rightIndex].fromOldList)
          (leftIndex: current[rightIndex].index, rightIndex: rightIndex),
    ];
  }

  ({List<TextDiffRange> left, List<TextDiffRange> right}) _characterRanges(
    String left,
    String right,
  ) {
    final leftCharacters = left.characters.toList(growable: false);
    final rightCharacters = right.characters.toList(growable: false);
    final leftTokens = [
      for (var index = 0; index < leftCharacters.length; index++)
        _IndexedToken(
          index: index,
          normalized: leftCharacters[index],
          fromOldList: true,
        ),
    ];
    final rightTokens = [
      for (var index = 0; index < rightCharacters.length; index++)
        _IndexedToken(
          index: index,
          normalized: rightCharacters[index],
          fromOldList: false,
        ),
    ];
    final current = List<_IndexedToken>.of(leftTokens);
    final removed = <int>{};
    final inserted = <int>{};
    final diff = calculateListDiff<_IndexedToken>(
      leftTokens,
      rightTokens,
      detectMoves: false,
      equalityChecker: (a, b) => a.normalized == b.normalized,
    );
    for (final update in diff.getUpdatesWithData()) {
      update.when(
        insert: (position, data) {
          inserted.add(data.index);
          current.insert(position, data);
        },
        remove: (position, data) {
          removed.add(data.index);
          current.removeAt(position);
        },
        change: (_, _, _) {},
        move: (_, _, _) {},
      );
    }
    return (
      left: _mergeCharacterRanges(leftCharacters, removed),
      right: _mergeCharacterRanges(rightCharacters, inserted),
    );
  }

  List<TextDiffRange> _mergeCharacterRanges(
    List<String> characters,
    Set<int> changed,
  ) {
    final offsets = List<int>.filled(characters.length + 1, 0);
    for (var index = 0; index < characters.length; index++) {
      offsets[index + 1] = offsets[index] + characters[index].length;
    }
    final ranges = <TextDiffRange>[];
    int? start;
    for (var index = 0; index <= characters.length; index++) {
      final isChanged = index < characters.length && changed.contains(index);
      if (isChanged && start == null) start = index;
      if (!isChanged && start != null) {
        ranges.add(TextDiffRange(start: offsets[start], end: offsets[index]));
        start = null;
      }
    }
    return ranges;
  }

  List<String> _splitLines(String text) {
    if (text.isEmpty) return const [];
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  }

  String _normalize(String value, TextCompareOptions options) {
    var normalized = value;
    if (options.ignoreTrailingWhitespace) {
      normalized = normalized.replaceFirst(RegExp(r'[ \t]+$'), '');
    }
    if (options.ignoreCase) normalized = normalized.toLowerCase();
    return normalized;
  }
}

class _IndexedToken {
  const _IndexedToken({
    required this.index,
    required this.normalized,
    required this.fromOldList,
  });

  final int index;
  final String normalized;
  final bool fromOldList;
}
