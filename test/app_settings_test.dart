import 'package:flutter_test/flutter_test.dart';

import 'package:dev_orbit/core/settings/app_settings.dart';

void main() {
  test('persists the clipboard diagnostics setting', () {
    final defaults = AppSettings.defaults();
    expect(defaults.clipboardTraceEnabled, isTrue);

    final disabled = defaults.copyWith(clipboardTraceEnabled: false);
    final restored = AppSettings.fromJson(disabled.toJson());

    expect(restored.clipboardTraceEnabled, isFalse);
  });
}
