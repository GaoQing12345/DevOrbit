import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dev_orbit/core/settings/app_settings.dart';

void main() {
  test('clipboard diagnostics stay off unless enabled', () {
    final defaults = AppSettings.defaults();
    expect(defaults.clipboardTraceEnabled, isFalse);

    final enabled = defaults.copyWith(clipboardTraceEnabled: true);
    final restored = AppSettings.fromJson(enabled.toJson());
    expect(restored.clipboardTraceEnabled, isTrue);
  });

  test('settings saved before the diagnostics toggle default to off', () {
    final json = AppSettings.defaults().toJson()
      ..remove('clipboardTraceEnabled');

    expect(
      AppSettings.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      ).clipboardTraceEnabled,
      isFalse,
    );
  });
}
