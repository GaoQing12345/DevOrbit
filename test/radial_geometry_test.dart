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

  test('clamps the launcher inside a display work area', () {
    final bounds = RadialGeometry.clampToWorkArea(
      cursor: const Offset(10, 10),
      windowSize: const Size.square(360),
      workArea: const Rect.fromLTWH(0, 0, 1440, 900),
    );

    expect(bounds.topLeft, Offset.zero);
    expect(bounds.size, const Size.square(360));
  });
}
