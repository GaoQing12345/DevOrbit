import 'dart:math' as math;

import 'package:flutter/material.dart';

class OrbitRingPainter extends CustomPainter {
  const OrbitRingPainter({
    required this.hoveredIndex,
    required this.hoveredColor,
  });

  static const slotCount = 8;
  static const _lineColor = Color(0x241C2A32);

  final int? hoveredIndex;
  final Color hoveredColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = size.shortestSide / 2 - 4;
    final innerRadius = size.shortestSide * 0.205;
    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);

    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(outerRect)
      ..addOval(innerRect);
    final trackPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.45),
        radius: 1.05,
        colors: [Color(0xE8FFFFFF), Color(0xB8E9F0EF)],
      ).createShader(outerRect);

    canvas.drawShadow(ring, const Color(0x380B1B20), 20, false);
    canvas.drawPath(ring, trackPaint);

    if (hoveredIndex case final index?) {
      _paintHoveredSegment(
        canvas,
        center: center,
        innerRadius: innerRadius,
        outerRadius: outerRadius,
        index: index,
      );
    }

    _paintDividers(canvas, center, innerRadius, outerRadius);
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xB8FFFFFF),
    );
    canvas.drawCircle(
      center,
      innerRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x521C2A32),
    );
  }

  void _paintHoveredSegment(
    Canvas canvas, {
    required Offset center,
    required double innerRadius,
    required double outerRadius,
    required int index,
  }) {
    final sweep = 2 * math.pi / slotCount;
    final start = -math.pi / 2 + index * sweep - sweep / 2;
    final segment = Path()
      ..arcTo(
        Rect.fromCircle(center: center, radius: outerRadius - 2),
        start,
        sweep,
        false,
      )
      ..arcTo(
        Rect.fromCircle(center: center, radius: innerRadius + 2),
        start + sweep,
        -sweep,
        false,
      )
      ..close();

    canvas.drawPath(segment, Paint()..color = hoveredColor.withAlpha(54));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius - 2),
      start + 0.05,
      sweep - 0.1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = hoveredColor.withAlpha(210),
    );
  }

  void _paintDividers(
    Canvas canvas,
    Offset center,
    double innerRadius,
    double outerRadius,
  ) {
    final paint = Paint()
      ..strokeWidth = 0.8
      ..color = _lineColor;
    for (var index = 0; index < slotCount; index++) {
      final angle = -math.pi / 2 + (index + 0.5) * 2 * math.pi / slotCount;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (innerRadius + 5),
        center + direction * (outerRadius - 6),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant OrbitRingPainter oldDelegate) {
    return hoveredIndex != oldDelegate.hoveredIndex ||
        hoveredColor != oldDelegate.hoveredColor;
  }
}
