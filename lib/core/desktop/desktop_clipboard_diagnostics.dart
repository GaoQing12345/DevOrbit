import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Writes a short cross-layer trace for clipboard investigations.
///
/// Off by default; [configure] turns it on from the settings page. Clipboard
/// contents are intentionally never written. The file lives in the system temp
/// directory so it never accumulates inside the app bundle.
class DesktopClipboardDiagnostics {
  const DesktopClipboardDiagnostics._();

  static const fileName = 'dev_orbit_clipboard_trace.log';
  static const _channel = MethodChannel('dev_orbit/clipboard');
  static Future<void> _pendingWrite = Future<void>.value();
  static bool _enabled = false;

  static bool get enabled => _enabled;

  static void configure(bool enabled) {
    _enabled = enabled;
    unawaited(_configureNative(enabled));
  }

  static String get path =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName';

  static void write(String event, [Map<String, Object?> fields = const {}]) {
    if (!_enabled || Platform.environment['DEV_ORBIT_CLIPBOARD_TRACE'] == '0') {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    final details = fields.entries
        .map((entry) => '${entry.key}=${_sanitize(entry.value)}')
        .join(' ');
    final line =
        '$timestamp pid=$pid '
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

  static Future<void> _configureNative(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setDiagnosticsEnabled', {
        'enabled': enabled,
      });
    } on Object {
      // The native runner treats the setting as optional.
    }
  }

  static String _sanitize(Object? value) {
    if (value == null) return 'null';
    final text = value.toString().replaceAll(RegExp(r'[\r\n\t ]+'), '_');
    return text.length <= 160 ? text : '${text.substring(0, 157)}...';
  }
}
