import 'package:dev_orbit/features/translator/translator_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('translator occupies the second radial slot', () {
    final module = TranslatorModule();

    expect(module.descriptor.radialSlot, 1);
  });
}
