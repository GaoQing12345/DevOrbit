import 'package:dev_orbit/core/desktop/window_blur_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ignores a blur superseded by a focus event', () async {
    final guard = WindowBlurGuard(
      isFocused: () async => false,
      settleDelay: Duration.zero,
    );

    final shouldDismiss = guard.shouldDismissAfterBlur();
    guard.handleFocus();

    expect(await shouldDismiss, isFalse);
  });

  test('ignores a blur when the window has regained focus', () async {
    final guard = WindowBlurGuard(
      isFocused: () async => true,
      settleDelay: Duration.zero,
    );

    expect(await guard.shouldDismissAfterBlur(), isFalse);
  });

  test('confirms a blur when the window remains unfocused', () async {
    final guard = WindowBlurGuard(
      isFocused: () async => false,
      settleDelay: Duration.zero,
    );

    expect(await guard.shouldDismissAfterBlur(), isTrue);
  });
}
