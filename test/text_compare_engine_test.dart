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
}
