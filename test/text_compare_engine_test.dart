import 'package:dev_orbit/features/text_compare/text_compare_engine.dart';
import 'package:dev_orbit/features/text_compare/text_compare_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = TextCompareEngine();

  test('returns no changes for identical text', () {
    final result = engine.compare(
      left: 'alpha\nbeta',
      right: 'alpha\nbeta',
      options: const TextCompareOptions(),
    );

    expect(result.hasChanges, isFalse);
    expect(
      result.leftLines.map((line) => line.status),
      everyElement(TextDiffLineStatus.unchanged),
    );
  });

  test('pairs replacements and keeps extra inserted and removed lines', () {
    final result = engine.compare(
      left: 'keep\nold one\nold two\nremoved\ntail',
      right: 'keep\nnew one\nnew two\ntail\nadded',
      options: const TextCompareOptions(),
    );

    expect(result.modifiedCount, 2);
    expect(result.removedCount, 1);
    expect(result.addedCount, 1);
    expect(result.leftLines[1].status, TextDiffLineStatus.modified);
    expect(result.leftLines[3].status, TextDiffLineStatus.removed);
    expect(result.rightLines[4].status, TextDiffLineStatus.added);
  });

  test('reports UTF-16 ranges while diffing Unicode graphemes', () {
    const family = '👨‍👩‍👧‍👦';
    final result = engine.compare(
      left: 'a${family}b',
      right: 'a🙂b',
      options: const TextCompareOptions(),
    );

    expect(result.modifiedCount, 1);
    expect(result.leftLines.single.ranges.single.start, 1);
    expect(result.leftLines.single.ranges.single.end, 1 + family.length);
    expect(result.rightLines.single.ranges.single.start, 1);
    expect(result.rightLines.single.ranges.single.end, 3);
  });

  test('supports ignore case and trailing whitespace rules', () {
    final exact = engine.compare(
      left: 'Hello  ',
      right: 'hello',
      options: const TextCompareOptions(),
    );
    final ignored = engine.compare(
      left: 'Hello  ',
      right: 'hello',
      options: const TextCompareOptions(
        ignoreCase: true,
        ignoreTrailingWhitespace: true,
      ),
    );

    expect(exact.modifiedCount, 1);
    expect(ignored.hasChanges, isFalse);
  });

  test('preserves blank lines and terminal newline', () {
    final result = engine.compare(
      left: 'alpha\n\nomega',
      right: 'alpha\n\nomega\n',
      options: const TextCompareOptions(),
    );

    expect(result.addedCount, 1);
    expect(result.rightLines.last.status, TextDiffLineStatus.added);
  });

  test('normalizes line-ending encoding', () {
    final result = engine.compare(
      left: 'alpha\r\nbeta',
      right: 'alpha\nbeta',
      options: const TextCompareOptions(),
    );

    expect(result.hasChanges, isFalse);
  });

  test('handles repeated lines without move detection', () {
    final result = engine.compare(
      left: 'same\nrepeat\nrepeat\nend',
      right: 'same\nrepeat\nchanged\nrepeat\nend',
      options: const TextCompareOptions(),
    );

    expect(result.addedCount, 1);
    expect(result.modifiedCount, 0);
    expect(result.removedCount, 0);
  });

  test('ignores leading whitespace on every line, not only the first', () {
    const left = '  alpha\n\tbeta\n    gamma';
    const right = 'alpha\nbeta\ngamma';

    final exact = engine.compare(
      left: left,
      right: right,
      options: const TextCompareOptions(),
    );
    final ignored = engine.compare(
      left: left,
      right: right,
      options: const TextCompareOptions(ignoreLeadingWhitespace: true),
    );

    expect(exact.modifiedCount, 3);
    expect(ignored.hasChanges, isFalse);
    expect(
      ignored.leftLines.map((line) => line.status),
      everyElement(TextDiffLineStatus.unchanged),
    );
  });

  test('keeps ignored indentation out of the character highlight', () {
    const left = '    foo bar';
    const right = '  foo baz';
    final result = engine.compare(
      left: left,
      right: right,
      options: const TextCompareOptions(ignoreLeadingWhitespace: true),
    );

    expect(result.modifiedCount, 1);
    // Only the "r"/"z" differ, and the indentation stays out of the highlight.
    expect(result.leftLines.single.ranges, [
      const TextDiffRange(start: 10, end: 11),
    ]);
    expect(result.rightLines.single.ranges, [
      const TextDiffRange(start: 8, end: 9),
    ]);
  });

  test('only ignores whitespace inside the line when asked', () {
    const left = 'total  =  1';
    const right = 'total = 1';
    const edges = TextCompareOptions(
      ignoreLeadingWhitespace: true,
      ignoreTrailingWhitespace: true,
    );

    expect(
      engine.compare(left: left, right: right, options: edges).hasChanges,
      isTrue,
    );
    expect(
      engine
          .compare(
            left: left,
            right: right,
            options: const TextCompareOptions(ignoreAllWhitespace: true),
          )
          .hasChanges,
      isFalse,
    );
  });

  test('skips blank and whitespace-only lines', () {
    const options = TextCompareOptions(ignoreBlankLines: true);
    final result = engine.compare(
      left: 'alpha\n\n\nomega',
      right: 'alpha\n   \nomega\n',
      options: options,
    );

    expect(result.hasChanges, isFalse);
    expect(result.leftLines, hasLength(4));
    expect(result.rightLines, hasLength(4));
  });

  test('can ignore the newline at the end of the file', () {
    const left = 'alpha\nbeta\n';
    const right = 'alpha\nbeta';

    final exact = engine.compare(
      left: left,
      right: right,
      options: const TextCompareOptions(),
    );
    final ignored = engine.compare(
      left: left,
      right: right,
      options: const TextCompareOptions(ignoreTrailingNewline: true),
    );

    expect(exact.removedCount, 1);
    expect(ignored.hasChanges, isFalse);
  });

  test('pairs the closest line when a change block gains a line', () {
    final result = engine.compare(
      left: 'head\nresult = compute();\ntail',
      right: 'head\nlog("start");\nresult = compute2();\ntail',
      options: const TextCompareOptions(),
    );

    expect(result.addedCount, 1);
    expect(result.modifiedCount, 1);
    expect(result.removedCount, 0);
    expect(result.rightLines[1].status, TextDiffLineStatus.added);
    expect(result.rightLines[2].status, TextDiffLineStatus.modified);
    expect(result.leftLines[1].status, TextDiffLineStatus.modified);
  });

  test('highlights the changed word instead of the whole line', () {
    const left = 'const total = price + tax;';
    const right = 'const total = price + vat;';
    final result = engine.compare(
      left: left,
      right: right,
      options: const TextCompareOptions(),
    );

    expect(result.leftLines.single.ranges, [
      const TextDiffRange(start: 22, end: 25),
    ]);
    expect(result.rightLines.single.ranges, [
      const TextDiffRange(start: 22, end: 25),
    ]);
  });

  test('diffs Chinese text character by character', () {
    const left = '今天天气很好';
    const right = '今天天气不错';
    final result = engine.compare(
      left: left,
      right: right,
      options: const TextCompareOptions(),
    );

    expect(result.leftLines.single.ranges, [
      const TextDiffRange(start: 4, end: 6),
    ]);
  });

  test('moves the highlight with an inserted line', () {
    final result = engine.compare(
      left: 'one\ntwo\nthree',
      right: 'one\ninserted\ntwo\nthree',
      options: const TextCompareOptions(),
    );

    expect(result.addedCount, 1);
    expect(result.modifiedCount, 0);
    expect(result.hunks, hasLength(1));
    expect(result.hunks.single.rightIndex, 1);
    expect(result.hunks.single.leftIndex, 1);
  });

  test('reports one hunk per change block so navigation can jump', () {
    final result = engine.compare(
      left: 'a\nb\nc\nd\ne',
      right: 'a\nB\nc\nd\nE',
      options: const TextCompareOptions(),
    );

    expect(result.hunks, hasLength(2));
    expect(result.hunks.first.leftIndex, 1);
    expect(result.hunks.first.modified, 1);
    expect(result.hunks.last.leftIndex, 4);
  });

  group('line pairing for the scroll sync', () {
    test('maps every line one to one when the texts match', () {
      final result = engine.compare(
        left: 'a\nb\nc',
        right: 'a\nb\nc',
        options: const TextCompareOptions(),
      );

      expect(result.leftToRight, [0, 1, 2]);
      expect(result.rightToLeft, [0, 1, 2]);
    });

    test('carries an inserted line into the pairing of the following lines', () {
      final result = engine.compare(
        left: 'a\nb\nc',
        right: 'a\nnew1\nnew2\nb\nc',
        options: const TextCompareOptions(),
      );

      expect(result.leftToRight, hasLength(3));
      expect(result.rightToLeft, hasLength(5));
      // `b` and `c` keep their own counterparts; the inserted lines borrow the
      // line above them so both sequences stay monotonic.
      expect(result.leftToRight[1], 3);
      expect(result.leftToRight[2], 4);
      expect(result.rightToLeft[3], 1);
      expect(result.rightToLeft[4], 2);
      expect(result.rightToLeft[1], result.rightToLeft[0]);
      expect(result.rightToLeft[2], result.rightToLeft[1]);
    });

    test('keeps a removed line on the previous pair until the next one', () {
      final result = engine.compare(
        left: 'a\nb\nc\nd',
        right: 'a\nd',
        options: const TextCompareOptions(),
      );

      expect(result.rightToLeft, hasLength(2));
      expect(result.rightToLeft[0], 0);
      expect(result.rightToLeft[1], 3);
      // `b` and `c` have no counterpart of their own, so they keep the line
      // above them and the pane only moves once `d` is reached.
      expect(result.leftToRight[1], 0);
      expect(result.leftToRight[2], 0);
      expect(result.leftToRight[3], 1);
    });

    test('pairs the lines of a rewrite position by position', () {
      final result = engine.compare(
        left: 'keep\nold one\nold two\ntail',
        right: 'keep\nnew one\nnew two\ntail',
        options: const TextCompareOptions(),
      );

      expect(result.leftToRight, [0, 1, 2, 3]);
      expect(result.rightToLeft, [0, 1, 2, 3]);
    });

    test('leaves the pairing empty when one side has nothing to pair', () {
      final result = engine.compare(
        left: 'a\nb',
        right: '',
        options: const TextCompareOptions(),
      );

      expect(result.leftToRight, everyElement(-1));
      expect(result.rightToLeft, isEmpty);
    });

    test('stays inside the other side for every index', () {
      final result = engine.compare(
        left: 'a\nb\nc\nd\ne\nf',
        right: 'a\nX\nd\ne\nY\nZ\nf',
        options: const TextCompareOptions(),
      );

      for (final index in result.leftToRight) {
        expect(index, inInclusiveRange(0, result.rightToLeft.length - 1));
      }
      for (final index in result.rightToLeft) {
        expect(index, inInclusiveRange(0, result.leftToRight.length - 1));
      }
    });
  });
}
