import 'dart:async';

import 'package:dev_orbit/features/sql_log/sql_log_controller.dart';
import 'package:dev_orbit/features/sql_log/sql_log_converter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/inline_sql_log_conversion_service.dart';

void main() {
  test(
    'a conversion that finishes late does not overwrite a newer one',
    () async {
      final conversion = _ControlledConversion();
      final controller = SqlLogController(conversion: conversion);
      addTearDown(controller.dispose);
      final newer = SqlLogConversionResult(
        statements: const [],
        diagnostics: const ['newer'],
      );

      controller.updateSource('first', immediate: true);
      controller.updateSource('second', immediate: true);
      await pumpEventQueue();

      expect(conversion.sources, ['first', 'second']);

      // The older request resolves last, which is exactly what happens when a
      // large log is still parsing while the user keeps typing.
      conversion.pending[1].complete(newer);
      await pumpEventQueue();
      expect(controller.result, same(newer));

      conversion.pending[0].complete(SqlLogConversionResult.empty);
      await pumpEventQueue();
      expect(controller.result, same(newer));
    },
  );

  test('clearing drops an in-flight conversion', () async {
    final conversion = _ControlledConversion();
    final controller = SqlLogController(conversion: conversion);
    addTearDown(controller.dispose);

    controller.updateSource('select 1', immediate: true);
    await pumpEventQueue();
    controller.clear();

    conversion.pending.single.complete(
      SqlLogConversionResult(statements: const [], diagnostics: const ['late']),
    );
    await pumpEventQueue();

    expect(controller.result.output, isEmpty);
  });

  test('clearing cancels the debounced conversion', () async {
    final conversion = _ControlledConversion();
    final controller = SqlLogController(conversion: conversion);
    addTearDown(controller.dispose);

    controller.updateSource('select 1');
    controller.clear();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(conversion.sources, isEmpty);
    expect(controller.result.output, isEmpty);
  });

  test('clipboard import awaits the conversion it started', () async {
    final controller = SqlLogController(
      conversion: const InlineSqlLogConversionService(),
    );
    addTearDown(controller.dispose);

    final imported = await controller.importRecognizedLog(
      'select * from t where id = ?\n'
      'Parameters: 8(Long)',
    );

    expect(imported, isTrue);
    expect(controller.result.output, contains('8'));
  });

  test(
    'the isolate service produces the same result as the inline one',
    () async {
      const source =
          '==> Preparing: select * from users where name = ?\n'
          '==> Parameters: Alice(String)';

      final isolate = await const IsolateSqlLogConversionService().convert(
        source,
        SqlLogDialect.mysql,
      );
      final inline = await const InlineSqlLogConversionService().convert(
        source,
        SqlLogDialect.mysql,
      );

      expect(isolate.output, inline.output);
      expect(isolate.statements, hasLength(1));
    },
  );
}

class _ControlledConversion implements SqlLogConversionService {
  final List<String> sources = [];
  final List<Completer<SqlLogConversionResult>> pending = [];

  @override
  Future<SqlLogConversionResult> convert(String source, SqlLogDialect dialect) {
    sources.add(source);
    final completer = Completer<SqlLogConversionResult>();
    pending.add(completer);
    return completer.future;
  }
}
