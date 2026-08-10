import 'package:dev_orbit/core/desktop/launch_at_startup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a hidden macOS launch agent and escapes XML', () {
    final plist = buildMacOSLaunchAgent(
      label: 'com.example.dev&orbit',
      bundlePath: '/Applications/Dev<Orbit>.app',
    );

    expect(plist, contains('com.example.dev&amp;orbit'));
    expect(plist, contains('/Applications/Dev&lt;Orbit&gt;.app'));
    expect(plist, contains('<string>--hidden</string>'));
    expect(plist, contains('<key>RunAtLoad</key>'));
  });
}
