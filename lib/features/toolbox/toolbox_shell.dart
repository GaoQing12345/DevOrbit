import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/modules/tool_registry.dart';
import '../../core/settings/settings_store.dart';
import '../settings/settings_page.dart';
import 'toolbox_home.dart';
import 'windows_toolbox_title_bar.dart';

class ToolboxShell extends StatelessWidget {
  const ToolboxShell({
    super.key,
    required this.controller,
    required this.registry,
    required this.settings,
    this.showWindowControls,
  });

  final AppController controller;
  final ToolRegistry registry;
  final SettingsStore settings;
  final bool? showWindowControls;

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (!(showWindowControls ?? Platform.isWindows)) return content;
    return Column(
      children: [
        WindowsToolboxTitleBar(controller: controller),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final selectedIndex = _selectedIndex();
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          _Sidebar(
            controller: controller,
            registry: registry,
            selectedIndex: selectedIndex,
          ),
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                Visibility(
                  visible: selectedIndex == 0,
                  maintainState: true,
                  child: ToolboxHome(
                    controller: controller,
                    registry: registry,
                  ),
                ),
                Visibility(
                  visible: selectedIndex == 1,
                  maintainState: true,
                  child: SettingsPage(
                    controller: controller,
                    settings: settings,
                  ),
                ),
                for (var index = 0; index < registry.modules.length; index++)
                  Visibility(
                    visible: selectedIndex == index + 2,
                    maintainState: true,
                    child: registry.modules[index].buildPage(),
                  ),
              ],
            ),
          ),
        ],
      ),
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
      width: 232,
      child: ColoredBox(
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(10, 4, 10, 24),
                child: Row(
                  children: [
                    _OrbitMark(),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'DevOrbit',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _NavItem(
                icon: Icons.grid_view_rounded,
                label: '工具箱',
                selected: selectedIndex == 0,
                onTap: controller.showToolbox,
              ),
              const SizedBox(height: 6),
              for (var index = 0; index < registry.modules.length; index++) ...[
                _NavItem(
                  icon: registry.modules[index].descriptor.icon,
                  label: registry.modules[index].descriptor.title,
                  selected: selectedIndex == index + 2,
                  onTap: () => controller.openTool(
                    registry.modules[index].descriptor.id,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              const Spacer(),
              _NavItem(
                icon: Icons.settings_outlined,
                label: '设置',
                selected: selectedIndex == 1,
                onTap: controller.showSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              const SizedBox(width: 13),
              Icon(icon, size: 19),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbitMark extends StatelessWidget {
  const _OrbitMark();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 24,
            height: 12,
            decoration: BoxDecoration(
              border: Border.all(color: accent, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(dimension: 7),
          ),
        ],
      ),
    );
  }
}
