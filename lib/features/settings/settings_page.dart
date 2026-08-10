import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../app/app_controller.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_store.dart';

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
        return ListView(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
          children: [
            Text('设置', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
            _SettingsSection(
              title: '启动',
              children: [
                _SettingsRow(
                  title: '全局快捷键',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HotKeyVirtualView(hotKey: value.hotKey),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => _recordHotKey(context, value.hotKey),
                        child: const Text('更改'),
                      ),
                    ],
                  ),
                ),
                if (controller.hotKeyError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      controller.hotKeyError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                _SettingsRow(
                  title: '开机启动',
                  trailing: Switch(
                    value: value.launchAtStartup,
                    onChanged: controller.updateLaunchAtStartup,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SettingsSection(
              title: '编辑器',
              children: [
                _SettingsRow(
                  title: '缩进宽度',
                  trailing: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2 空格')),
                      ButtonSegment(value: 4, label: Text('4 空格')),
                    ],
                    selected: {value.indentSize},
                    onSelectionChanged: (selection) {
                      controller.updateIndent(selection.first);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SettingsSection(
              title: '外观',
              children: [
                _SettingsRow(
                  title: '主题',
                  trailing: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
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
            const SizedBox(height: 28),
            const _SettingsSection(
              title: '关于',
              children: [
                _SettingsRow(title: 'DevOrbit', trailing: Text('0.1.0')),
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
    return AlertDialog(
      title: const Text('设置全局快捷键'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(6),
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
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index < children.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 24),
          trailing,
        ],
      ),
    );
  }
}
