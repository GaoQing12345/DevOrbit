import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

/// Registers DevOrbit as a login item through a per-user LaunchAgent.
///
/// The app ships outside the App Store and without a sandbox, so a plain
/// `~/Library/LaunchAgents` plist is enough and keeps the setting auditable by
/// the user.
class LaunchAtStartupService {
  String? _appPath;
  String? _packageName;

  Future<void> setup() async {
    final info = await PackageInfo.fromPlatform();
    _appPath = Platform.resolvedExecutable;
    _packageName = info.packageName;
  }

  Future<bool> setEnabled(bool enabled) async {
    try {
      final file = _launchAgentFile();
      if (file == null) return false;
      if (!enabled) {
        if (await file.exists()) await file.delete();
        return !await file.exists();
      }

      final bundlePath = path.dirname(path.dirname(path.dirname(_appPath!)));
      if (!bundlePath.endsWith('.app')) return false;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        buildMacOSLaunchAgent(label: _packageName!, bundlePath: bundlePath),
        flush: true,
      );
      // Awaited so a failure here lands in the same `catch` as the write.
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  File? _launchAgentFile() {
    final home = Platform.environment['HOME'];
    final packageName = _packageName;
    if (home == null || !path.isAbsolute(home) || packageName == null) {
      return null;
    }
    if (!RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(packageName)) return null;
    return File(
      path.join(home, 'Library', 'LaunchAgents', '$packageName.plist'),
    );
  }
}

String buildMacOSLaunchAgent({
  required String label,
  required String bundlePath,
}) {
  final escapedLabel = _escapeXml(label);
  final escapedBundlePath = _escapeXml(bundlePath);
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$escapedLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-gj</string>
    <string>$escapedBundlePath</string>
    <string>--args</string>
    <string>--hidden</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
