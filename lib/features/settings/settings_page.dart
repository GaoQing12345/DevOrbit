import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_controller.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_store.dart';
import '../../core/widgets/mac_ui.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final AppController controller;
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: settings,
      builder: (context, value, child) {
        return MacPageScaffold(
          title: '设置',
          children: [
            MacGroup(
              title: '启动',
              children: [
                MacRow(
                  title: '全局快捷键',
                  description: '在任何应用中唤出工具轮盘',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HotKeyVirtualView(hotKey: value.hotKey),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _recordHotKey(context, value.hotKey),
                        child: const Text('更改'),
                      ),
                    ],
                  ),
                ),
                if (controller.hotKeyError != null)
                  MacRow(
                    title: '快捷键无效',
                    description: controller.hotKeyError,
                    trailing: Icon(
                      Icons.error_outline_rounded,
                      size: 15,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                MacRow(
                  title: '开机启动',
                  description: '登录 macOS 后自动在菜单栏运行',
                  trailing: _MacSwitch(
                    value: value.launchAtStartup,
                    onChanged: controller.updateLaunchAtStartup,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            MacGroup(
              title: '编辑器',
              children: [
                MacRow(
                  title: '缩进',
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: '2', label: Text('2')),
                      ButtonSegment(value: '4', label: Text('4')),
                      ButtonSegment(value: '8', label: Text('8')),
                      ButtonSegment(value: 'tab', label: Text('Tab')),
                    ],
                    selected: {
                      value.indentWithTabs ? 'tab' : '${value.indentSize}',
                    },
                    onSelectionChanged: (selection) {
                      final choice = selection.first;
                      if (choice == 'tab') {
                        controller.updateIndentWithTabs(true);
                      } else {
                        // Picking a width also switches back to spaces.
                        controller.updateIndent(int.parse(choice));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            MacGroup(
              title: '外观',
              children: [
                MacRow(
                  title: '主题',
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_rounded, size: 14),
                        tooltip: '跟随系统',
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 14),
                        tooltip: '浅色',
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 14),
                        tooltip: '深色',
                      ),
                    ],
                    selected: {value.themeMode},
                    onSelectionChanged: (selection) {
                      controller.updateTheme(selection.first);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            MacGroup(
              title: '诊断',
              children: [
                MacRow(
                  title: '剪贴板诊断日志',
                  description: '排查粘贴问题时记录事件到控制台',
                  trailing: _MacSwitch(
                    value: value.clipboardTraceEnabled,
                    onChanged: controller.updateClipboardTrace,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            MacGroup(
              title: '关于',
              children: [
                MacRow(
                  title: 'DevOrbit',
                  description: '面向开发者的 macOS 工具箱',
                  trailing: _VersionLabel(),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _recordHotKey(BuildContext context, HotKey current) async {
    final hotKey = await showDialog<HotKey>(
      context: context,
      builder: (context) => _HotKeyDialog(current: current),
    );
    if (hotKey != null) await controller.updateHotKey(hotKey);
  }
}

/// macOS switch geometry is 38x22; Material's is 52x32, which reads as a web
/// control. Scaling keeps the Material state animations but matches the size.
class _MacSwitch extends StatelessWidget {
  const _MacSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.74,
      alignment: Alignment.centerRight,
      child: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _HotKeyDialog extends StatefulWidget {
  const _HotKeyDialog({required this.current});

  final HotKey current;

  @override
  State<_HotKeyDialog> createState() => _HotKeyDialogState();
}

class _HotKeyDialogState extends State<_HotKeyDialog> {
  HotKey? _recorded;
  String? _error;

  void _save() {
    final hotKey = _recorded;
    if (hotKey == null || (hotKey.modifiers?.isEmpty ?? true)) {
      setState(() => _error = '快捷键至少需要一个修饰键');
      return;
    }
    Navigator.pop(context, hotKey);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('设置全局快捷键'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: HotKeyRecorder(
                initalHotKey: widget.current,
                onHotKeyRecorded: (hotKey) {
                  _recorded = HotKey(
                    identifier: 'dev-orbit-launcher',
                    key: hotKey.key,
                    modifiers: hotKey.modifiers,
                  );
                  setState(() => _error = null);
                },
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

/// Shows the version the bundle was built with instead of a hard-coded string
/// that goes stale on the first release bump.
class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  // The bundle version cannot change while the process runs.
  static final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return Text('—', style: style);
        final build = info.buildNumber;
        return Text(
          build.isEmpty ? info.version : '${info.version}+$build',
          style: style,
        );
      },
    );
  }
}
