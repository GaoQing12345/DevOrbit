import 'package:dev_orbit/features/sql_log/sql_log_clipboard_import.dart';
import 'package:dev_orbit/features/sql_log/sql_log_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports and converts recognizable MyBatis clipboard content', () async {
    final controller = SqlLogController();
    addTearDown(controller.dispose);

    final imported = await importSqlLogClipboard(
      controller: controller,
      readClipboard: () async => const ClipboardData(
        text:
            'select * from t where id = ?\n'
            'Parameters: 8(Long)',
      ),
    );

    expect(imported, isTrue);
    expect(controller.result.statements, hasLength(1));
    expect(controller.result.output, contains('8'));
  });

  test('leaves the input blank for unrelated clipboard content', () async {
    final controller = SqlLogController();
    addTearDown(controller.dispose);

    final imported = await importSqlLogClipboard(
      controller: controller,
      readClipboard: () async => const ClipboardData(text: 'ordinary text'),
    );

    expect(imported, isFalse);
    expect(controller.sourceText, isEmpty);
    expect(controller.result.output, isEmpty);
  });
}
