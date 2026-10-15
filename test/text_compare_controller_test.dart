import 'dart:async';

import 'package:dev_orbit/features/text_compare/text_compare_controller.dart';
import 'package:dev_orbit/features/text_compare/text_compare_engine.dart';
import 'package:dev_orbit/features/text_compare/text_compare_models.dart';
import 'package:dev_orbit/features/text_compare/text_compare_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compares manually and invalidates highlights after editing', () async {
    final controller = TextCompareController(service: _ImmediateService());
    controller.updateLeft('old');
    controller.updateRight('new');

    await controller.compare();

    expect(controller.status, TextCompareStatus.changed);
    expect(controller.result?.modifiedCount, 1);
    expect(controller.canCopySummary, isTrue);

    controller.updateRight('newer');

    expect(controller.status, TextCompareStatus.stale);
    expect(controller.result, isNull);
    expect(controller.canCopySummary, isFalse);
  });

  test('discards a result if content changes while comparing', () async {
    final completer = Completer<TextDiffResult>();
    final controller = TextCompareController(
      service: _CompleterService(completer),
    );
    controller.updateLeft('before');
    controller.updateRight('after');

    final comparing = controller.compare();
    controller.updateRight('changed again');
    completer.complete(
      const TextDiffResult(
        leftLines: [],
        rightLines: [],
        addedCount: 0,
        removedCount: 0,
        modifiedCount: 1,
      ),
    );
    await comparing;

    expect(controller.isComparing, isFalse);
    expect(controller.status, TextCompareStatus.stale);
    expect(controller.result, isNull);
  });

  test('swaps content and builds the compact summary', () async {
    final controller = TextCompareController(service: _ImmediateService());
    controller.updateLeft('left');
    controller.updateRight('right');
    controller.updateIgnoreCase(true);

    controller.swap();

    expect(controller.leftText, 'right');
    expect(controller.rightText, 'left');
    await controller.compare();
    expect(controller.buildSummary(), contains('新增 0 行，删除 0 行，修改 1 行'));
    expect(controller.buildSummary(), contains('规则：忽略大小写'));
  });

  test('rejects text larger than ten MiB before starting service', () async {
    final service = _CountingService();
    final controller = TextCompareController(service: service);
    controller.updateLeft('a' * (textCompareMaxBytes + 1));

    await controller.compare();

    expect(service.calls, 0);
    expect(controller.status, TextCompareStatus.error);
    expect(controller.errorMessage, contains('10 MiB'));
  });

  test('refreshes the diff by itself shortly after an edit', () async {
    final controller = TextCompareController(service: _ImmediateService());
    addTearDown(controller.dispose);

    controller.updateLeft('old line');
    controller.updateRight('new line');
    expect(controller.result, isNull);

    await Future<void>.delayed(_autoCompareWait);

    expect(controller.status, TextCompareStatus.changed);
    expect(controller.result?.modifiedCount, 1);
  });

  test('re-runs the comparison as soon as a rule is toggled', () async {
    final controller = TextCompareController(service: _ImmediateService());
    addTearDown(controller.dispose);

    controller.updateLeft('  value  ');
    controller.updateRight('value');
    await Future<void>.delayed(_autoCompareWait);
    expect(controller.status, TextCompareStatus.changed);

    controller.updateIgnoreAllWhitespace(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.status, TextCompareStatus.unchanged);
    expect(controller.canCopySummary, isTrue);
  });

  test('keeps the whitespace rules mutually exclusive', () {
    final controller = TextCompareController(
      service: _ImmediateService(),
      autoCompare: false,
    );
    addTearDown(controller.dispose);

    controller.updateIgnoreLeadingWhitespace(true);
    controller.updateIgnoreTrailingWhitespace(true);
    controller.updateIgnoreAllWhitespace(true);

    expect(controller.options.ignoreAllWhitespace, isTrue);
    expect(controller.options.ignoreLeadingWhitespace, isFalse);
    expect(controller.options.ignoreTrailingWhitespace, isFalse);

    controller.updateIgnoreTrailingWhitespace(true);

    expect(controller.options.ignoreAllWhitespace, isFalse);
    expect(controller.options.ignoreTrailingWhitespace, isTrue);
  });

  test('lists every active rule in the copied summary', () async {
    final controller = TextCompareController(service: _ImmediateService());
    addTearDown(controller.dispose);
    controller.updateLeft('alpha\n');
    controller.updateRight('ALPHA');
    controller.updateIgnoreCase(true);
    controller.updateIgnoreTrailingNewline(true);

    await controller.compare();
    final summary = controller.buildSummary();

    expect(summary, contains('规则：忽略大小写、忽略末尾换行'));
    expect(summary, contains('未发现差异'));
  });

  test('exposes the change blocks for the diff navigation', () async {
    final controller = TextCompareController(
      service: _ImmediateService(),
      autoCompare: false,
    );
    addTearDown(controller.dispose);
    controller.updateLeft('a\nb\nc');
    controller.updateRight('a\nB\nc\nd');

    await controller.compare();

    expect(controller.hunks, hasLength(2));
    expect(controller.hunks.first.leftIndex, 1);
    expect(controller.hunks.last.added, 1);
  });

  test('cancels the pending automatic comparison when disposed', () async {
    final service = _CountingService();
    final controller = TextCompareController(service: service);
    controller.updateLeft('left');
    controller.updateRight('right');

    controller.dispose();
    await Future<void>.delayed(_autoCompareWait);

    expect(service.calls, 0);
  });
}

final _autoCompareWait = TextCompareController.autoCompareDelay * 2;

class _ImmediateService implements TextCompareService {
  @override
  Future<TextDiffResult> compare({
    required String left,
    required String right,
    required TextCompareOptions options,
  }) async {
    return const TextCompareEngine().compare(
      left: left,
      right: right,
      options: options,
    );
  }
}

class _CompleterService implements TextCompareService {
  _CompleterService(this.completer);

  final Completer<TextDiffResult> completer;

  @override
  Future<TextDiffResult> compare({
    required String left,
    required String right,
    required TextCompareOptions options,
  }) => completer.future;
}

class _CountingService implements TextCompareService {
  int calls = 0;

  @override
  Future<TextDiffResult> compare({
    required String left,
    required String right,
    required TextCompareOptions options,
  }) async {
    calls++;
    return const TextDiffResult(
      leftLines: [],
      rightLines: [],
      addedCount: 0,
      removedCount: 0,
      modifiedCount: 0,
    );
  }
}
