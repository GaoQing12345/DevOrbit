import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../core/modules/tool_registry.dart';
import '../../core/settings/settings_store.dart';
import '../../core/widgets/lazy_indexed_stack.dart';
import '../../core/widgets/mac_ui.dart';
import '../settings/settings_page.dart';
import 'toolbox_home.dart';

class ToolboxShell extends StatelessWidget {
  const ToolboxShell({
    super.key,
    required this.controller,
    required this.registry,
    required this.settings,
  });

  final AppController controller;
  final ToolRegistry registry;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex();
    return Row(
      children: [
        _Sidebar(
          controller: controller,
          registry: registry,
          selectedIndex: selectedIndex,
        ),
        Expanded(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: LazyIndexedStack(
              index: selectedIndex,
              children: [
                ToolboxHome(controller: controller, registry: registry),
                SettingsPage(controller: controller, settings: settings),
                for (final module in registry.modules) module.buildPage(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _selectedIndex() {
    if (controller.mode == AppViewMode.toolbox) {
      return controller.section == ToolboxSection.settings ? 1 : 0;
    }
    if (controller.mode == AppViewMode.tool) {
      final index = registry.modules.indexWhere(
        (module) => module.descriptor.id == controller.selectedToolId,
      );
      if (index >= 0) return index + 2;
    }
    return 0;
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.registry,
    required this.selectedIndex,
  });

  final AppController controller;
  final ToolRegistry registry;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 214,
      child: ColoredBox(
        color: scheme.surfaceContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 12, 9),
              child: Row(
                children: [
                  const OrbitMark(size: 17),
                  const SizedBox(width: 7),
                  Text(
                    'DevOrbit',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                children: [
                  _SidebarRow(
                    icon: Icons.grid_view_rounded,
                    label: '工具箱',
                    selected: selectedIndex == 0,
                    onTap: controller.showToolbox,
                  ),
                  const SizedBox(height: 12),
                  const _SidebarHeading('工具'),
                  for (var index = 0; index < registry.modules.length; index++)
                    _SidebarRow(
                      icon: registry.modules[index].descriptor.icon,
                      label: registry.modules[index].descriptor.title,
                      selected: selectedIndex == index + 2,
                      onTap: () => controller.openTool(
                        registry.modules[index].descriptor.id,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: scheme.outlineVariant.withAlpha(150),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: _SidebarRow(
                icon: Icons.settings_outlined,
                label: '设置',
                selected: selectedIndex == 1,
                onTap: controller.showSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 28pt-high source-list row: accent fill when selected, grey wash on hover.
/// macOS has no ripple, so the press state is a flat darker fill.
class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final selected = widget.selected;
    final foreground = selected
        ? scheme.onPrimary
        : (theme.brightness == Brightness.dark
              ? scheme.onSurface
              : const Color(0xFF3A3A3C));
    final background = selected
        ? (_pressed ? scheme.primary.withAlpha(220) : scheme.primary)
        : (_pressed
              ? scheme.onSurface.withAlpha(30)
              : (_hovered
                    ? scheme.onSurface.withAlpha(18)
                    : Colors.transparent));

    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            height: 28,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(
              children: [
                Icon(widget.icon, size: 15, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarHeading extends StatelessWidget {
  const _SidebarHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
