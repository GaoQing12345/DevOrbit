import 'package:dev_orbit/features/sql_log/sql_log_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SQL log converter occupies the fifth radial slot', () {
    final descriptor = SqlLogModule().descriptor;

    expect(descriptor.id, 'sql-log-converter');
    expect(descriptor.title, 'SQL 日志还原');
    expect(descriptor.radialSlot, 4);
  });
}
