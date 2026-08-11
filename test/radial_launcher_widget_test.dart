import 'dart:ui';

import 'package:dev_orbit/app/app_controller.dart';
import 'package:dev_orbit/core/desktop/desktop_shell.dart';
import 'package:dev_orbit/core/modules/tool_module.dart';
import 'package:dev_orbit/core/modules/tool_registry.dart';
import 'package:dev_orbit/features/launcher/orbit_ring_painter.dart';
import 'package:dev_orbit/core/settings/settings_store.dart';
import 'package:dev_orbit/features/launcher/radial_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows eight slots and opens an enabled tool', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final module = _WidgetTestModule();
    final registry = ToolRegistry([module]);
    final shell = _FakeDesktopShell();
    final controller = AppController(
      registry: registry,
      settings: settings,
      shell: shell,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          dimension: 360,
          child: RadialLauncher(controller: controller, registry: registry),
        ),
      ),
    );

    expect(find.byType(IconButton), findsNWidgets(9));
    await tester.tap(find.byIcon(Icons.code_rounded));
    await tester.pump();

    expect(module.launchCount, 1);
    expect(shell.toolWindowShows, 1);
    expect(controller.mode, AppViewMode.tool);
  });

  testWidgets('highlights the orbit segment under the pointer', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final registry = ToolRegistry([_WidgetTestModule()]);
    final controller = AppController(
      registry: registry,
      settings: settings,
      shell: _FakeDesktopShell(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.square(
          dimension: 360,
          child: RadialLauncher(controller: controller, registry: registry),
        ),
      ),
    );

    final ring = find.byKey(const ValueKey('orbit-ring-track'));
    expect(ring, findsOneWidget);
    expect(
      (tester.widget<CustomPaint>(ring).painter! as OrbitRingPainter)
          .hoveredIndex,
      isNull,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.code_rounded)));
    await tester.pumpAndSettle();

    expect(
      (tester.widget<CustomPaint>(ring).painter! as OrbitRingPainter)
          .hoveredIndex,
      0,
    );

    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.grid_view_rounded)));
    await tester.pumpAndSettle();

    expect(
      (tester.widget<CustomPaint>(ring).painter! as OrbitRingPainter)
          .hoveredIndex,
      isNull,
    );
  });
}

class _WidgetTestModule implements ToolModule {
  int launchCount = 0;

  @override
  ToolDescriptor get descriptor => const ToolDescriptor(
    id: 'test-tool',
    title: '测试工具',
    description: '测试',
    icon: Icons.code_rounded,
    radialSlot: 0,
    accentColor: Colors.teal,
  );

  @override
  Widget buildPage() => const SizedBox();

  @override
  Future<void> onLaunch(ToolLaunchContext context) async {
    launchCount++;
  }
}

class _FakeDesktopShell implements DesktopShell {
  int toolWindowShows = 0;

  @override
  Future<void> hide() async {}

  @override
  Future<String?> initialize(
    DesktopShellCallbacks callbacks,
    HotKey hotKey,
  ) async => null;

  @override
  Future<void> quit() async {}

  @override
  Future<bool> setLaunchAtStartup(bool enabled) async => true;

  @override
  Future<void> showRadial() async {}

  @override
  Future<void> showToolWindow({bool focus = true}) async {
    toolWindowShows++;
  }

  @override
  Future<String?> updateHotKey(HotKey hotKey) async => null;
}
