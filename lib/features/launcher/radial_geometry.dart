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
    final maxLeft = math.max(workArea.left, workArea.right - windowSize.width);
    final maxTop = math.max(workArea.top, workArea.bottom - windowSize.height);
    final left = (cursor.dx - windowSize.width / 2).clamp(
      workArea.left,
      maxLeft,
    );
    final top = (cursor.dy - windowSize.height / 2).clamp(workArea.top, maxTop);
    return Rect.fromLTWH(left, top, windowSize.width, windowSize.height);
  }
}
