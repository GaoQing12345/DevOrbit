import 'package:dev_orbit/features/text_compare/text_compare_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text compare occupies the third radial slot', () {
    final module = TextCompareModule();

    expect(module.descriptor.id, 'text-compare');
    expect(module.descriptor.radialSlot, 2);
  });
}
