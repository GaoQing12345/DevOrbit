import 'package:dev_orbit/app/app_theme.dart';
import 'package:dev_orbit/core/desktop/desktop_window_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Escape closes the active desktop window', (tester) async {
    var closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopEscapeCloseRegion(
          onClose: () async => closeCount++,
          child: const Scaffold(body: TextField(autofocus: true)),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('Escape closes a desktop window without an editable focus', (
    tester,
  ) async {
    var closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopEscapeCloseRegion(
          onClose: () async => closeCount++,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('Windows window controls are visible before hover', (
    tester,
  ) async {
    var minimizeCount = 0;
    var closeCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: WindowsWindowTitleBar(
            title: 'DevOrbit',
            onMinimize: () => minimizeCount++,
            onClose: () => closeCount++,
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(WindowsWindowTitleBar));
    final expectedColor = Theme.of(context).colorScheme.onSurface;
    final minimizeIcon = tester.widget<Icon>(find.byIcon(Icons.remove_rounded));
    final closeIcon = tester.widget<Icon>(find.byIcon(Icons.close_rounded));
    expect(minimizeIcon.color, expectedColor);
    expect(closeIcon.color, expectedColor);

    await tester.tap(find.byTooltip('最小化'));
    await tester.tap(find.byTooltip('关闭'));
    expect(minimizeCount, 1);
    expect(closeCount, 1);
  });
}
