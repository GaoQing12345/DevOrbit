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
            width: 6,
            child: _DiffStripe(
              controller: controller,
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
    required this.controller,
    required this.notifier,
    required this.lines,
    required this.scheme,
  });

  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final List<TextDiffLine> lines;
  final ColorScheme scheme;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _DiffStripeRenderObject(controller, notifier, lines, scheme);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _DiffStripeRenderObject renderObject,
  ) {
    renderObject
      ..controller = controller
      ..notifier = notifier
      ..lines = lines
      ..scheme = scheme;
  }
}

class _DiffStripeRenderObject extends RenderBox {
  _DiffStripeRenderObject(
    this._controller,
    this._notifier,
    this._lines,
    this._scheme,
  ) {
    _notifier.addListener(markNeedsPaint);
  }

  CodeLineEditingController _controller;
  CodeIndicatorValueNotifier _notifier;
  List<TextDiffLine> _lines;
  ColorScheme _scheme;

  set controller(CodeLineEditingController value) {
    if (identical(_controller, value)) return;
    _controller = value;
    markNeedsPaint();
  }

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
      final originalIndex = _controller.codeLines.index2lineIndex(
        paragraph.index,
      );
      if (originalIndex < 0 || originalIndex >= _lines.length) continue;
      final color = switch (_lines[originalIndex].status) {
        TextDiffLineStatus.added => const Color(0xFF2E9B63),
        TextDiffLineStatus.removed =>
          _scheme.brightness == Brightness.dark
              ? const Color(0xFFFF716B)
              : const Color(0xFFCC332E),
        TextDiffLineStatus.modified => const Color(0xFFE0991B),
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
