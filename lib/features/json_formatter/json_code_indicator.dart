import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

class JsonCodeIndicator extends StatelessWidget {
  const JsonCodeIndicator({
    super.key,
    required this.editingController,
    required this.chunkController,
    required this.notifier,
  });

  final CodeLineEditingController editingController;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lineNumberStyle = TextStyle(
      color: colors.onSurfaceVariant.withAlpha(145),
      fontSize: 12,
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['Consolas', 'monospace'],
    );
    return ColoredBox(
      color: colors.surfaceContainerLowest.withAlpha(110),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 6),
          DefaultCodeLineNumber(
            controller: editingController,
            notifier: notifier,
            textStyle: lineNumberStyle,
            focusedTextStyle: lineNumberStyle.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          DefaultCodeChunkIndicator(
            key: const ValueKey('json-fold-indicator'),
            width: 26,
            controller: chunkController,
            notifier: notifier,
            painter: JsonCodeChunkIndicatorPainter(
              backgroundColor: colors.primary.withAlpha(18),
              borderColor: colors.primary.withAlpha(58),
              iconColor: colors.primary,
            ),
          ),
          const SizedBox(width: 3),
        ],
      ),
    );
  }
}

class JsonCodeChunkIndicatorPainter implements CodeChunkIndicatorPainter {
  JsonCodeChunkIndicatorPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;

  @override
  void paintCollapseIndicator(Canvas canvas, Size container) {
    _paintIndicator(canvas, container, expanded: true);
  }

  @override
  void paintExpandIndicator(Canvas canvas, Size container) {
    _paintIndicator(canvas, container, expanded: false);
  }

  void _paintIndicator(
    Canvas canvas,
    Size container, {
    required bool expanded,
  }) {
    if (container.isEmpty) return;
    final side = math.min(15.0, container.height - 3).clamp(10.0, 15.0);
    final rect = Rect.fromCenter(
      center: container.center(Offset.zero),
      width: side,
      height: side,
    );
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(shape, Paint()..color = backgroundColor);
    canvas.drawRRect(
      shape,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _paintChevron(canvas, rect.center, expanded: expanded);
  }

  void _paintChevron(Canvas canvas, Offset center, {required bool expanded}) {
    final path = Path();
    if (expanded) {
      path
        ..moveTo(center.dx - 3, center.dy - 1.5)
        ..lineTo(center.dx, center.dy + 1.5)
        ..lineTo(center.dx + 3, center.dy - 1.5);
    } else {
      path
        ..moveTo(center.dx - 1.5, center.dy - 3)
        ..lineTo(center.dx + 1.5, center.dy)
        ..lineTo(center.dx - 1.5, center.dy + 3);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = iconColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}
