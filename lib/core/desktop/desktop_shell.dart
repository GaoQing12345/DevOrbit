import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/launcher/radial_geometry.dart';
import 'launch_at_startup_service.dart';
import 'window_blur_guard.dart';

class DesktopShellCallbacks {
  const DesktopShellCallbacks({
    required this.onToggleRadial,
    required this.onOpenToolbox,
    required this.onOpenSettings,
    required this.onCloseRequested,
    required this.onWindowBlur,
  });

  final Future<void> Function() onToggleRadial;
  final Future<void> Function() onOpenToolbox;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onCloseRequested;
  final VoidCallback onWindowBlur;
}

abstract interface class DesktopShell {
  Future<String?> initialize(DesktopShellCallbacks callbacks, HotKey hotKey);
  Future<void> showRadial();
  Future<void> showToolWindow({bool focus = true});
  Future<void> hide();
  Future<void> minimize();
  Future<void> quit();
  Future<String?> updateHotKey(HotKey hotKey);
  Future<bool> setLaunchAtStartup(bool enabled);
}

class NativeDesktopShell
    with WindowListener, TrayListener
    implements DesktopShell {
  static const radialSize = Size.square(360);
  static const toolSize = Size(960, 700);
  static const toolMinimumSize = Size(760, 520);
  static const _maximumSize = Size(10000, 10000);

  DesktopShellCallbacks? _callbacks;
  HotKey? _hotKey;
  final LaunchAtStartupService _launchAtStartup = LaunchAtStartupService();
  final WindowBlurGuard _windowBlurGuard = WindowBlurGuard(
    isFocused: windowManager.isFocused,
  );
  Rect _lastToolBounds = const Rect.fromLTWH(120, 100, 960, 700);

  @override
  Future<String?> initialize(
    DesktopShellCallbacks callbacks,
    HotKey hotKey,
  ) async {
    _callbacks = callbacks;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: toolSize,
        minimumSize: toolMinimumSize,
        center: true,
        backgroundColor: Colors.transparent,
        title: 'DevOrbit',
      ),
    );
    await _rememberToolBounds();
    await _setupTray();
    await _launchAtStartup.setup();
    return updateHotKey(hotKey);
  }

  Future<void> _setupTray() async {
    final icon = Platform.isWindows
        ? 'assets/icons/tray_icon.ico'
        : 'assets/icons/tray_icon.png';
    await trayManager.setIcon(icon, isTemplate: Platform.isMacOS);
    await trayManager.setToolTip('DevOrbit');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'radial', label: '打开轮盘'),
          MenuItem(key: 'toolbox', label: '打开工具箱'),
          MenuItem(key: 'settings', label: '设置'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出 DevOrbit'),
        ],
      ),
    );
  }

  @override
  Future<void> showRadial() async {
    if (await windowManager.isVisible()) {
      await _rememberToolBounds();
    }
    final cursor = await screenRetriever.getCursorScreenPoint();
    final workArea = await _workAreaFor(cursor);
    final bounds = RadialGeometry.centerInWorkArea(
      windowSize: radialSize,
      workArea: workArea,
    );
    await windowManager.setMinimumSize(const Size(1, 1));
    await windowManager.setMaximumSize(_maximumSize);
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setBounds(bounds);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _rememberToolBounds() async {
    final bounds = await windowManager.getBounds();
    if (bounds.width < toolMinimumSize.width ||
        bounds.height < toolMinimumSize.height) {
      return;
    }
    _lastToolBounds = bounds;
  }

  Future<Rect> _workAreaFor(Offset point) async {
    final displays = await screenRetriever.getAllDisplays();
    for (final display in displays) {
      final position = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      final rect = position & size;
      if (rect.contains(point)) return rect;
    }
    final primary = await screenRetriever.getPrimaryDisplay();
    return (primary.visiblePosition ?? Offset.zero) &
        (primary.visibleSize ?? primary.size);
  }

  @override
  Future<void> showToolWindow({bool focus = true}) async {
    await windowManager.setMaximumSize(_maximumSize);
    await windowManager.setMinimumSize(toolMinimumSize);
    await windowManager.setResizable(true);
    await windowManager.setHasShadow(true);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    final useCustomWindowsTitleBar = Platform.isWindows;
    await windowManager.setTitleBarStyle(
      useCustomWindowsTitleBar ? TitleBarStyle.hidden : TitleBarStyle.normal,
      windowButtonVisibility: !useCustomWindowsTitleBar,
    );
    await windowManager.setBounds(_lastToolBounds);
    await windowManager.show(inactive: !focus);
    if (focus) await windowManager.focus();
  }

  @override
  Future<void> hide() async {
    if (await windowManager.isVisible()) await _rememberToolBounds();
    await windowManager.hide();
  }

  @override
  Future<void> minimize() {
    return windowManager.minimize();
  }

  @override
  Future<void> quit() async {
    await trayManager.destroy();
    await hotKeyManager.unregisterAll();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  Future<String?> updateHotKey(HotKey hotKey) async {
    final previous = _hotKey;
    try {
      if (previous != null) await hotKeyManager.unregister(previous);
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) => _callbacks?.onToggleRadial(),
      );
      _hotKey = hotKey;
      return null;
    } catch (error) {
      if (previous != null) {
        try {
          await hotKeyManager.register(
            previous,
            keyDownHandler: (_) => _callbacks?.onToggleRadial(),
          );
        } catch (rollbackError) {
          _hotKey = null;
          return '快捷键注册失败：$error；恢复原快捷键失败：$rollbackError';
        }
      }
      return '快捷键注册失败：$error';
    }
  }

  @override
  Future<bool> setLaunchAtStartup(bool enabled) {
    return _launchAtStartup.setEnabled(enabled);
  }

  @override
  void onWindowClose() {
    _callbacks?.onCloseRequested();
  }

  @override
  void onWindowFocus() {
    _windowBlurGuard.handleFocus();
  }

  @override
  void onWindowBlur() {
    _confirmWindowBlur();
  }

  Future<void> _confirmWindowBlur() async {
    if (await _windowBlurGuard.shouldDismissAfterBlur()) {
      _callbacks?.onWindowBlur();
    }
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'radial':
        _callbacks?.onToggleRadial();
        break;
      case 'toolbox':
        _callbacks?.onOpenToolbox();
        break;
      case 'settings':
        _callbacks?.onOpenSettings();
        break;
      case 'quit':
        quit();
        break;
    }
  }
}
