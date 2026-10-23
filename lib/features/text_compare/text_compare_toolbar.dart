import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/widgets/mac_ui.dart';
import 'text_compare_controller.dart';

class CompareToolbar extends StatelessWidget {
  const CompareToolbar({
    super.key,
    required this.controller,
    required this.foldUnchanged,
    required this.showFoldUnchanged,
    required this.onFoldUnchangedChanged,
    required this.syncScroll,
    required this.onSyncScrollChanged,
    required this.onOpenLeft,
    required this.onOpenRight,
    required this.onCopySummary,
  });

  final TextCompareController controller;
  final bool foldUnchanged;
  final bool showFoldUnchanged;
  final ValueChanged<bool> onFoldUnchangedChanged;
  final bool syncScroll;
  final ValueChanged<bool> onSyncScrollChanged;
  final VoidCallback onOpenLeft;
  final VoidCallback onOpenRight;
  final VoidCallback onCopySummary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The legend is the first thing to go when the window gets narrow;
        // the diff counts stay readable in the status bar.
        final wide = constraints.maxWidth >= 880;
        return MacToolbar(
          leading: [
            const MacToolbarTitle('文本比对'),
            OutlinedButton.icon(
              onPressed: onOpenLeft,
              icon: const Icon(Icons.folder_open_rounded, size: 14),
              label: const Text('左侧文件'),
            ),
            OutlinedButton.icon(
              onPressed: onOpenRight,
              icon: const Icon(Icons.folder_open_rounded, size: 14),
              label: const Text('右侧文件'),
            ),
            _OptionsMenu(
              controller: controller,
              foldUnchanged: foldUnchanged,
              showFoldUnchanged: showFoldUnchanged,
              onFoldUnchangedChanged: onFoldUnchangedChanged,
              syncScroll: syncScroll,
              onSyncScrollChanged: onSyncScrollChanged,
            ),
          ],
          trailing: [
            if (wide) const _DiffLegend(),
            FilledButton.icon(
              onPressed: controller.canCompare ? controller.compare : null,
              icon: controller.isComparing
                  ? const SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.difference_rounded, size: 14),
              label: Text(controller.isComparing ? '比对中' : '开始比对'),
            ),
            IconButton(
              tooltip: '交换左右文本',
              icon: const Icon(Icons.swap_horiz_rounded),
              onPressed:
                  controller.leftText.isEmpty && controller.rightText.isEmpty
                  ? null
                  : controller.swap,
            ),
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed:
                  controller.leftText.isEmpty && controller.rightText.isEmpty
                  ? null
                  : controller.clear,
            ),
            IconButton(
              tooltip: '复制比对摘要',
              icon: const Icon(Icons.content_copy_rounded),
              onPressed: controller.canCopySummary ? onCopySummary : null,
            ),
          ],
        );
      },
    );
  }
}

/// Pop-up holding the diff rules. Keeping them in a menu is the macOS idiom:
/// the toolbar stays one row wide, and the active rules are echoed in the
/// status bar so they never become invisible state.
class _OptionsMenu extends StatelessWidget {
  const _OptionsMenu({
    required this.controller,
    required this.foldUnchanged,
    required this.showFoldUnchanged,
    required this.onFoldUnchangedChanged,
    required this.syncScroll,
    required this.onSyncScrollChanged,
  });

  final TextCompareController controller;
  final bool foldUnchanged;
  final bool showFoldUnchanged;
  final ValueChanged<bool> onFoldUnchangedChanged;
  final bool syncScroll;
  final ValueChanged<bool> onSyncScrollChanged;

  static const _ruleTooltips = {
    '忽略行首空白': '每行开头的缩进差异不计入比对结果',
    '忽略行尾空白': '每行结尾的空格与制表符不计入比对结果',
    '忽略所有空白': '连同行内的空格一起忽略，选中后行首/行尾规则自动取消',
    '忽略空行': '空白行或只有空格的行不参与比对',
    '忽略末尾换行': '文本结尾多一个或少一个换行不算差异',
    '同步滚动': '滚到某一侧时，另一侧跟着滚到对应的那一行',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = controller.options;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
        elevation: const WidgetStatePropertyAll(12),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusPanel),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      menuChildren: [
        _CheckItem(
          label: '忽略大小写',
          value: options.ignoreCase,
          onChanged: controller.updateIgnoreCase,
          tooltip: _ruleTooltips['忽略大小写'],
        ),
        _CheckItem(
          label: '忽略行首空白',
          value: options.ignoreLeadingWhitespace,
          onChanged: controller.updateIgnoreLeadingWhitespace,
          tooltip: _ruleTooltips['忽略行首空白'],
        ),
        _CheckItem(
          label: '忽略行尾空白',
          value: options.ignoreTrailingWhitespace,
          onChanged: controller.updateIgnoreTrailingWhitespace,
          tooltip: _ruleTooltips['忽略行尾空白'],
        ),
        _CheckItem(
          label: '忽略所有空白',
          value: options.ignoreAllWhitespace,
          onChanged: controller.updateIgnoreAllWhitespace,
          tooltip: _ruleTooltips['忽略所有空白'],
        ),
        _CheckItem(
          label: '忽略空行',
          value: options.ignoreBlankLines,
          onChanged: controller.updateIgnoreBlankLines,
          tooltip: _ruleTooltips['忽略空行'],
        ),
        _CheckItem(
          label: '忽略末尾换行',
          value: options.ignoreTrailingNewline,
          onChanged: controller.updateIgnoreTrailingNewline,
          tooltip: _ruleTooltips['忽略末尾换行'],
        ),
        Divider(height: 9, color: scheme.outlineVariant),
        _CheckItem(
          label: '同步滚动',
          value: syncScroll,
          onChanged: onSyncScrollChanged,
          tooltip: _ruleTooltips['同步滚动'],
        ),
        if (showFoldUnchanged)
          _CheckItem(
            label: '折叠未更改行',
            value: foldUnchanged,
            onChanged: onFoldUnchangedChanged,
          ),
      ],
      builder: (context, controller, child) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.tune_rounded, size: 14),
        label: const Text('选项'),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  const _CheckItem({
    required this.label,
    required this.value,
    required this.onChanged,
    this.tooltip,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = MenuItemButton(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(196, 26)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        textStyle: WidgetStatePropertyAll(theme.textTheme.labelLarge),
      ),
      onPressed: () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: value
                ? Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: theme.colorScheme.primary,
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
    final description = tooltip;
    if (description == null) return content;
    return Tooltip(message: description, child: content);
  }
}

class _DiffLegend extends StatelessWidget {
  const _DiffLegend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: scheme.error, label: '删除'),
          const SizedBox(width: 8),
          _LegendItem(color: AppTheme.warning, label: '修改'),
          const SizedBox(width: 8),
          _LegendItem(color: const Color(0xFF2E9B63), label: '新增'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
