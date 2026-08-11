import 'dart:ui';

import 'package:dev_orbit/features/launcher/radial_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const geometry = RadialGeometry(radius: 100);
  const size = Size.square(300);

  test('places the first slot above the center', () {
    final position = geometry.positionFor(0, size);

    expect(position.dx, closeTo(150, 0.001));
    expect(position.dy, closeTo(50, 0.001));
  });

  test('places the third slot to the right', () {
    final position = geometry.positionFor(2, size);

    expect(position.dx, closeTo(250, 0.001));
    expect(position.dy, closeTo(150, 0.001));
  });

  test('centers the launcher at the cursor', () {
    final bounds = RadialGeometry.clampToWorkArea(
      cursor: const Offset(2200, 500),
      windowSize: const Size.square(360),
      workArea: const Rect.fromLTWH(1440, 24, 1920, 1056),
    );

    expect(bounds.center, const Offset(2200, 500));
    expect(bounds.size, const Size.square(360));
  });

  test('keeps the launcher inside the display work area', () {
    final topLeft = RadialGeometry.clampToWorkArea(
      cursor: const Offset(1440, 24),
      windowSize: const Size.square(360),
      workArea: const Rect.fromLTWH(1440, 24, 1920, 1056),
    );
    final bottomRight = RadialGeometry.clampToWorkArea(
      cursor: const Offset(3360, 1080),
      windowSize: const Size.square(360),
      workArea: const Rect.fromLTWH(1440, 24, 1920, 1056),
    );

    expect(topLeft.topLeft, const Offset(1440, 24));
    expect(bottomRight.bottomRight, const Offset(3360, 1080));
  });
}
