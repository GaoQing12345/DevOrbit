import 'package:dev_orbit/features/sql_log/sql_log_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = SqlLogConverter();

  test('restores and formats the sample MyBatis SQL log', () {
    const source = '''
2026-08-17 09:03:03.409 [http-nio-8080-exec-6] DEBUG mapper - ==>  Preparing: SELECT dept_id, parent_id FROM SYS_DEPT where dept_id in ( ? , ? , ? , ? )
2026-08-17 09:03:03.409 [http-nio-8080-exec-6] DEBUG mapper - ==> Parameters: 0(String), 10000000(String), 20000001(String), 30000001(String)
''';

    final result = converter.convert(source);
    final output = _singleLine(result.output);

    expect(result.statements, hasLength(1));
    expect(result.statements.single.parameters, hasLength(4));
    expect(result.statements.single.placeholderCount, 4);
    expect(result.statements.single.substitutedCount, 4);
    expect(output, contains("'0'"));
    expect(output, contains("'10000000'"));
    expect(output, contains("'20000001'"));
    expect(output, contains("'30000001'"));
    expect(output, isNot(contains('?')));
    expect(result.warningCount, 0);
  });

  test('quotes values according to type and escapes single quotes', () {
    const source = '''
==> Preparing: insert into audit_log(id, name, enabled, deleted_at) values (?, ?, ?, ?)
==> Parameters: 42(Integer), O'Brien(String), true(Boolean), null
''';

    final output = _singleLine(converter.convert(source).output);

    expect(output, contains('42'));
    expect(output, contains("'O''Brien'"));
    expect(output, contains('TRUE'));
    expect(output, contains('NULL'));
  });

  test('processes every complete pair in one pasted log', () {
    const source = '''
==> Preparing: select * from users where id = ?
==> Parameters: 7(Long)
unrelated log line
==> Preparing: delete from sessions where owner = ?
==> Parameters: alice(String)
''';

    final result = converter.convert(source);

    expect(result.statements, hasLength(2));
    expect(_singleLine(result.statements[0].formattedSql), contains('id = 7'));
    expect(
      _singleLine(result.statements[1].formattedSql),
      contains("owner = 'alice'"),
    );
  });

  test('restores raw SQL followed by a Parameters log without Preparing', () {
    const source = '''
select u.user_id, u.login_name from sys_user u where u.user_id = ?
2026-08-17 10:39:45.017 [http-nio-8080-exec-3] DEBUG mapper - ==> Parameters: 1(Long)
''';

    final result = converter.convert(source);

    expect(result.statements, hasLength(1));
    expect(result.statements.single.placeholderCount, 1);
    expect(result.statements.single.substitutedCount, 1);
    expect(_singleLine(result.output), contains('u.user_id = 1'));
  });

  test('accepts Preparing and Parameters markers without arrows', () {
    const source = '''
2026-08-17 10:39:45.017 DEBUG mapper - Preparing: select * from t where id = ?
2026-08-17 10:39:45.017 DEBUG mapper - Parameters: 8(Long)
''';

    final result = converter.convert(source);

    expect(result.statements, hasLength(1));
    expect(_singleLine(result.output), contains('id = 8'));
  });

  test('keeps question marks inside literals identifiers and comments', () {
    const source = '''
==> Preparing: select '?' as literal, `?` as marker from t where id = ? /* ? */ and enabled = ?
==> Parameters: 9(Integer), false(Boolean)
''';

    final result = converter.convert(source);
    final statement = result.statements.single;
    final output = _singleLine(statement.formattedSql);

    expect(statement.placeholderCount, 2);
    expect(output, contains("'?'"));
    expect(output, contains('`?`'));
    expect(output, contains('id = 9'));
    expect(output, contains('enabled = FALSE'));
  });

  test('keeps PostgreSQL dollar strings and question operators', () {
    const source = r'''
==> Preparing: select $$?$$, data ?| array['a'] from events where id = ?
==> Parameters: 3(Long)
''';

    final result = converter.convert(source, dialect: SqlLogDialect.postgresql);

    expect(result.statements.single.placeholderCount, 1);
    expect(result.output, contains(r'$$?$$'));
    expect(result.output, contains('?|'));
    expect(_singleLine(result.output), contains('id = 3'));
  });

  test('preserves commas and parentheses inside parameter values', () {
    const source = '''
==> Preparing: select * from people where display_name = ? and note = ?
==> Parameters: last, first(String), a(b)(String)
''';

    final result = converter.convert(source);
    final parameters = result.statements.single.parameters;

    expect(parameters, hasLength(2));
    expect(parameters[0].value, 'last, first');
    expect(parameters[1].value, 'a(b)');
    expect(
      _singleLine(result.output),
      contains("display_name = 'last, first'"),
    );
  });

  test('keeps unmatched placeholders and reports count mismatches', () {
    const missing = '''
==> Preparing: select * from t where a = ? and b = ?
==> Parameters: 1(Integer)
''';
    const extra = '''
==> Preparing: select * from t where a = ?
==> Parameters: 1(Integer), 2(Integer)
''';

    final missingResult = converter.convert(missing);
    final extraResult = converter.convert(extra);

    expect(_singleLine(missingResult.output), contains('b = ?'));
    expect(missingResult.allWarnings.single, contains('未匹配的 ? 已保留'));
    expect(extraResult.allWarnings.single, contains('多余参数未使用'));
  });

  test('reports incomplete and orphaned log groups', () {
    const source = '''
==> Parameters: orphan(String)
==> Preparing: select * from t where id = ?
''';

    final result = converter.convert(source);

    expect(result.statements, hasLength(1));
    expect(result.diagnostics.single, contains('没有对应的 Preparing'));
    expect(result.statements.single.warnings, hasLength(2));
  });

  test('recognizes supported clipboard log shapes', () {
    expect(
      converter.looksLikeSupportedLog(
        '==> Preparing: select ?\n==> Parameters: 1(Integer)',
      ),
      isTrue,
    );
    expect(
      converter.looksLikeSupportedLog(
        'Preparing: select ?\nParameters: 1(Integer)',
      ),
      isTrue,
    );
    expect(
      converter.looksLikeSupportedLog(
        'select * from t where id = ?\nParameters: 1(Integer)',
      ),
      isTrue,
    );
    expect(converter.looksLikeSupportedLog('select * from t'), isFalse);
    expect(converter.looksLikeSupportedLog('==> Preparing: select ?'), isFalse);
  });
}

String _singleLine(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();
