import 'dart:math' as math;
import 'dart:ui';

class RadialGeometry {
  const RadialGeometry({this.radius = 112, this.slotCount = 8});

  final double radius;
  final int slotCount;

  Offset positionFor(int index, Size canvasSize) {
    if (index < 0 || index >= slotCount) {
      throw RangeError.index(index, List.filled(slotCount, null));
    }
    final angle = -math.pi / 2 + (2 * math.pi * index / slotCount);
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    return center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  static Rect clampToWorkArea({
    required Offset cursor,
    required Size windowSize,
    required Rect workArea,
  }) {
    final desired =
        cursor - Offset(windowSize.width / 2, windowSize.height / 2);
    final maxX = workArea.right - windowSize.width;
    final maxY = workArea.bottom - windowSize.height;
    return Rect.fromLTWH(
      desired.dx.clamp(workArea.left, maxX).toDouble(),
      desired.dy.clamp(workArea.top, maxY).toDouble(),
      windowSize.width,
      windowSize.height,
    );
  }
}
