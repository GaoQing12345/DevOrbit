import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'text_compare_models.dart';

class TextCompareIndicator extends StatelessWidget {
  const TextCompareIndicator({
    super.key,
    required this.controller,
    required this.notifier,
    required this.lines,
  });

  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final List<TextDiffLine> lines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineNumberStyle = TextStyle(
      color: scheme.onSurfaceVariant.withAlpha(145),
      fontSize: 12,
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['Consolas', 'monospace'],
    );
    return ColoredBox(
      color: scheme.surfaceContainerLowest.withAlpha(110),
      child: Stack(
        fit: StackFit.loose,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 9, right: 9),
            child: DefaultCodeLineNumber(
              controller: controller,
              notifier: notifier,
              textStyle: lineNumberStyle,
              focusedTextStyle: lineNumberStyle.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: _DiffStripe(
              notifier: notifier,
              lines: lines,
              scheme: scheme,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffStripe extends LeafRenderObjectWidget {
  const _DiffStripe({
    required this.notifier,
    required this.lines,
    required this.scheme,
  });

  final CodeIndicatorValueNotifier notifier;
  final List<TextDiffLine> lines;
  final ColorScheme scheme;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _DiffStripeRenderObject(notifier, lines, scheme);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _DiffStripeRenderObject renderObject,
  ) {
    renderObject
      ..notifier = notifier
      ..lines = lines
      ..scheme = scheme;
  }
}

class _DiffStripeRenderObject extends RenderBox {
  _DiffStripeRenderObject(this._notifier, this._lines, this._scheme) {
    _notifier.addListener(markNeedsPaint);
  }

  CodeIndicatorValueNotifier _notifier;
  List<TextDiffLine> _lines;
  ColorScheme _scheme;

  set notifier(CodeIndicatorValueNotifier value) {
    if (identical(_notifier, value)) return;
    _notifier.removeListener(markNeedsPaint);
    _notifier = value;
    _notifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set lines(List<TextDiffLine> value) {
    if (identical(_lines, value)) return;
    _lines = value;
    markNeedsPaint();
  }

  set scheme(ColorScheme value) {
    if (_scheme == value) return;
    _scheme = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final paragraphs = _notifier.value?.paragraphs ?? const [];
    for (final paragraph in paragraphs) {
      if (paragraph.index >= _lines.length) continue;
      final color = switch (_lines[paragraph.index].status) {
        TextDiffLineStatus.added => const Color(0xFF2E9B63),
        TextDiffLineStatus.removed => _scheme.error,
        TextDiffLineStatus.modified => const Color(0xFFD18A16),
        TextDiffLineStatus.unchanged => Colors.transparent,
      };
      if (color == Colors.transparent) continue;
      canvas.drawRect(
        Rect.fromLTRB(
          offset.dx,
          offset.dy + paragraph.top,
          offset.dx + size.width,
          offset.dy + paragraph.bottom,
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(markNeedsPaint);
    super.dispose();
  }
}
