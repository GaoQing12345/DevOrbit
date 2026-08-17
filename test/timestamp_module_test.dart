import 'package:dev_orbit/features/timestamp/timestamp_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timestamp converter occupies the fourth radial slot', () {
    final descriptor = TimestampModule().descriptor;

    expect(descriptor.id, 'timestamp-converter');
    expect(descriptor.title, '时间戳转换');
    expect(descriptor.radialSlot, 3);
  });
}
