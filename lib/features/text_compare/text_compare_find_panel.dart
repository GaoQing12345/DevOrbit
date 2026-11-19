import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'text_compare_models.dart';

class CompareFindPanel extends StatelessWidget {
  const CompareFindPanel({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.inputKey,
    required this.onFocus,
    required this.matchSide,
    required this.matchIndex,
    required this.matchCount,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Key inputKey;
  final VoidCallback onFocus;
  final TextCompareSide? matchSide;
  final int matchIndex;
  final int matchCount;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sideLabel = matchSide == TextCompareSide.left ? '左' : '右';
    final resultText = matchIndex < 0 || matchCount == 0 || matchSide == null
        ? '0/0'
        : '$sideLabel ${matchIndex + 1}/$matchCount';
    return Container(
      width: 336,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withAlpha(26),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): onNext,
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              },
              child: TextField(
                key: inputKey,
                controller: controller,
                focusNode: focusNode,
                onTap: onFocus,
                maxLines: 1,
                onEditingComplete: onNext,
                style: theme.textTheme.bodyMedium,
                decoration: const InputDecoration(
                  hintText: '查找',
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              resultText,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          _PanelButton(
            tooltip: '上一个',
            icon: Icons.keyboard_arrow_up_rounded,
            onPressed: matchCount == 0 ? null : onPrevious,
          ),
          _PanelButton(
            tooltip: '下一个',
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: matchCount == 0 ? null : onNext,
          ),
          _PanelButton(
            tooltip: '关闭查找',
            icon: Icons.close_rounded,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    );
  }
}
