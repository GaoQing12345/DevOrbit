import 'package:dev_orbit/core/desktop/desktop_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS uses the transparent template tray icon', () {
    expect(
      trayIconAsset(isMacOS: true, isWindows: false),
      'assets/icons/tray_icon_macos.png',
    );
  });

  test('Windows keeps using the ICO tray icon', () {
    expect(
      trayIconAsset(isMacOS: false, isWindows: true),
      'assets/icons/tray_icon.ico',
    );
  });
}
