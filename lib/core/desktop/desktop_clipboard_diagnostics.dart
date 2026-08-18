import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Writes a short cross-layer trace for desktop clipboard investigations.
///
/// Clipboard contents are intentionally never written. On Windows the file is
/// shared with the native runner through the system temp directory.
class DesktopClipboardDiagnostics {
  const DesktopClipboardDiagnostics._();

  static const fileName = 'dev_orbit_clipboard_trace.log';
  static Future<void> _pendingWrite = Future<void>.value();

  static String get path =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName';

  static void write(String event, [Map<String, Object?> fields = const {}]) {
    if (!_isDesktop ||
        Platform.environment['DEV_ORBIT_CLIPBOARD_TRACE'] == '0') {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    final details = fields.entries
        .map((entry) => '${entry.key}=${_sanitize(entry.value)}')
        .join(' ');
    final line =
        '$timestamp pid=$pid platform=${defaultTargetPlatform.name} '
        'event=$event${details.isEmpty ? '' : ' $details'}\n';
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await File(
          path,
        ).writeAsString(line, mode: FileMode.append, flush: true);
      } on Object {
        // Diagnostics must never affect clipboard behavior.
      }
    });
  }

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static String _sanitize(Object? value) {
    if (value == null) return 'null';
    final text = value.toString().replaceAll(RegExp(r'[\r\n\t ]+'), '_');
    return text.length <= 160 ? text : '${text.substring(0, 157)}...';
  }
}
