import 'package:material_ui/material_ui.dart';

import '../../core/widgets/mac_ui.dart';
import 'text_compare_controller.dart';
import 'text_compare_models.dart';

class CompareStatusBar extends StatelessWidget {
  const CompareStatusBar({
    super.key,
    required this.controller,
    required this.diffIndex,
    required this.foldUnchanged,
    required this.foldedLineCount,
    required this.onPreviousDiff,
    required this.onNextDiff,
  });

  final TextCompareController controller;
  final int diffIndex;
  final bool foldUnchanged;
  final int foldedLineCount;
  final VoidCallback onPreviousDiff;
  final VoidCallback onNextDiff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final result = controller.result;
    final hunks = controller.hunks;
    final text = switch (controller.status) {
      TextCompareStatus.idle => '准备就绪',
      TextCompareStatus.comparing => '正在比对文本',
      TextCompareStatus.unchanged => '两侧文本一致',
      TextCompareStatus.changed =>
        '新增 ${result?.addedCount ?? 0} 行 · 删除 ${result?.removedCount ?? 0} 行 · 修改 ${result?.modifiedCount ?? 0} 行',
      TextCompareStatus.stale => '内容已更改，请重新比对',
      TextCompareStatus.error => controller.errorMessage ?? '比对失败',
    };
    final color = switch (controller.status) {
      TextCompareStatus.error => scheme.error,
      TextCompareStatus.changed ||
      TextCompareStatus.stale => const Color(0xFFD18A16),
      TextCompareStatus.unchanged => const Color(0xFF2E9B63),
      _ => scheme.onSurfaceVariant,
    };
    final rules = controller.options.ruleLabels;
    return MacStatusBar(
      leading: [
        Icon(
          controller.isComparing
              ? Icons.sync_rounded
              : Icons.info_outline_rounded,
          size: 12,
          color: color,
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
        if (rules.isNotEmpty) _StatusCaption(text: '规则：${rules.join('、')}'),
        if (foldUnchanged)
          _StatusCaption(
            text: foldedLineCount > 0 ? '已折叠 $foldedLineCount 行' : '无可折叠行',
          ),
        _DiffNavigator(
          hunks: result == null ? 0 : hunks.length,
          ready: result != null,
          diffIndex: diffIndex,
          onPrevious: onPreviousDiff,
          onNext: onNextDiff,
        ),
      ],
    );
  }
}

class _StatusCaption extends StatelessWidget {
  const _StatusCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Counter plus the previous/next difference buttons. Mirrors the `F7` /
/// `Shift+F7` shortcuts that ship with every mainstream comparer.
class _DiffNavigator extends StatelessWidget {
  const _DiffNavigator({
    required this.hunks,
    required this.ready,
    required this.diffIndex,
    required this.onPrevious,
    required this.onNext,
  });

  final int hunks;
  final bool ready;
  final int diffIndex;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = hunks > 0;
    final String label;
    if (!ready) {
      label = '差异 –';
    } else if (hunks == 0) {
      label = '无差异';
    } else {
      label = diffIndex < 0 ? '差异 $hunks 处' : '差异 ${diffIndex + 1}/$hunks';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
        _NavButton(
          tooltip: '上一个差异 (⇧F7)',
          icon: Icons.keyboard_arrow_up_rounded,
          onPressed: enabled ? onPrevious : null,
        ),
        _NavButton(
          tooltip: '下一个差异 (F7)',
          icon: Icons.keyboard_arrow_down_rounded,
          onPressed: enabled ? onNext : null,
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
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
      constraints: const BoxConstraints.tightFor(width: 22, height: 22),
    );
  }
}
