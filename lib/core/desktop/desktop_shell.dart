import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/launcher/radial_geometry.dart';
import 'desktop_cursor_locator.dart';
import 'desktop_window_effects.dart';
import 'launch_at_startup_service.dart';
import 'window_blur_guard.dart';

/// macOS template image: the menu bar tints it for light and dark appearance.
const trayIconAsset = 'assets/icons/tray_icon_macos.png';

class DesktopShellCallbacks {
  const DesktopShellCallbacks({
    required this.onToggleRadial,
    required this.onOpenToolbox,
    required this.onOpenSettings,
    required this.onCloseRequested,
    required this.onQuitRequested,
    required this.onWindowBlur,
  });

  final Future<void> Function() onToggleRadial;
  final Future<void> Function() onOpenToolbox;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onCloseRequested;
  final Future<void> Function() onQuitRequested;
  final VoidCallback onWindowBlur;
}

abstract interface class DesktopShell {
  Future<String?> initialize(DesktopShellCallbacks callbacks, HotKey hotKey);
  Future<void> showRadial();
  Future<void> showToolWindow({bool focus = true});
  Future<void> hideRadial();
  Future<void> hide();
  Future<void> minimize();
  Future<void> quit();
  Future<String?> updateHotKey(HotKey hotKey);
  Future<bool> setLaunchAtStartup(bool enabled);
}

class NativeDesktopShell
    with WindowListener, TrayListener
    implements DesktopShell {
  NativeDesktopShell({
    DesktopWindowEffects? windowEffects,
    DesktopCursorLocator? cursorLocator,
  }) : _windowEffects = windowEffects ?? NativeDesktopWindowEffects(),
       _cursorLocator = cursorLocator ?? NativeDesktopCursorLocator();

  static const radialSize = Size.square(360);
  static const toolSize = Size(960, 700);
  static const toolMinimumSize = Size(760, 520);
  static const _maximumSize = Size(10000, 10000);
  static const _appLifecycleChannel = MethodChannel('dev_orbit/app_lifecycle');

  DesktopShellCallbacks? _callbacks;
  HotKey? _hotKey;
  final LaunchAtStartupService _launchAtStartup = LaunchAtStartupService();
  final DesktopWindowEffects _windowEffects;
  final DesktopCursorLocator _cursorLocator;
  final WindowBlurGuard _windowBlurGuard = WindowBlurGuard(
    isFocused: windowManager.isFocused,
  );
  Rect _lastToolBounds = const Rect.fromLTWH(120, 100, 960, 700);
  bool _radialWindowStyleActive = false;

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
      WindowOptions(
        size: toolSize,
        minimumSize: toolMinimumSize,
        center: true,
        title: 'DevOrbit',
      ),
    );
    await _rememberToolBounds();
    await _setupTray();
    await _launchAtStartup.setup();
    return updateHotKey(hotKey);
  }

  Future<void> _setupTray() async {
    await trayManager.setIcon(trayIconAsset, isTemplate: true);
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
    // The cursor position and the display list are served by different
    // channels and do not depend on each other. Awaiting them one after the
    // other added a full round trip to the hotkey-to-visible latency.
    final (cursor, displays) = await (
      _cursorLocator.getPosition(),
      screenRetriever.getAllDisplays(),
    ).wait;
    final bounds = RadialGeometry.clampToWorkArea(
      cursor: cursor,
      windowSize: radialSize,
      workArea: await _workAreaFor(cursor, displays),
    );
    _radialWindowStyleActive = true;
    // These window properties are independent of each other. They are still
    // dispatched in this order (transparency before the frame style, so the
    // first repaint after the style change already has a transparent
    // backdrop), but waiting for each reply in turn cost one IPC round trip
    // per call before the radial could appear.
    await Future.wait([
      windowManager.setMinimumSize(const Size(1, 1)),
      windowManager.setMaximumSize(_maximumSize),
      windowManager.setResizable(false),
      windowManager.setAlwaysOnTop(true),
      windowManager.setSkipTaskbar(true),
      windowManager.setBackgroundColor(Colors.transparent),
      windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
      windowManager.setHasShadow(false),
      _windowEffects.setRadialMode(true),
    ]);
    // Bounds and visibility must follow the size constraints above.
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

  Future<Rect> _workAreaFor(Offset point, List<Display> displays) async {
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
    await _ensureToolWindowStyle();
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
  Future<void> hideRadial() async {
    await windowManager.hide();
    await _ensureToolWindowStyle();
  }

  Future<void> _ensureToolWindowStyle() async {
    if (!_radialWindowStyleActive) return;

    // AppController starts standalone activation without awaiting this reset,
    // so the hidden main window is normalized without delaying tool display.
    await _restoreToolWindowStyle();
    _radialWindowStyleActive = false;
  }

  Future<void> _restoreToolWindowStyle() async {
    // Same reasoning as showRadial: independent properties, dispatched in
    // order but awaited together.
    await Future.wait([
      windowManager.setMaximumSize(_maximumSize),
      windowManager.setMinimumSize(toolMinimumSize),
      windowManager.setResizable(true),
      windowManager.setAlwaysOnTop(false),
      windowManager.setSkipTaskbar(false),
      windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      ),
      _windowEffects.setRadialMode(false),
      windowManager.setHasShadow(true),
    ]);
  }

  @override
  Future<void> minimize() {
    return windowManager.minimize();
  }

  @override
  Future<void> quit() async {
    // Drop the listeners before the native window goes away so a late focus or
    // tray event cannot call back into a torn-down shell.
    _detachListeners();
    await trayManager.destroy();
    await hotKeyManager.unregisterAll();
    await windowManager.setPreventClose(false);
    try {
      await _appLifecycleChannel.invokeMethod<void>('quit');
    } on MissingPluginException {
      await windowManager.destroy();
    } on PlatformException {
      await windowManager.destroy();
    }
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
        _callbacks?.onQuitRequested();
        break;
    }
  }

  /// Stops native event delivery. [quit] calls this on the way out; the shell
  /// outlives every widget, so there is nothing else to release here.
  void dispose() => _detachListeners();

  void _detachListeners() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }
}
