import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopClipboardReader {
  const DesktopClipboardReader();

  static const _channel = MethodChannel('dev_orbit/clipboard');

  Future<void> armPasteCapture(int sessionId) {
    return _invokeVoid('armPasteCapture', sessionId);
  }

  Future<void> discardPendingPasteText(int sessionId) {
    return _invokeVoid('discardPendingPasteText', sessionId);
  }

  Future<String?> readCapturedPasteText(int sessionId) async {
    if (!_usesNativeCapture) return null;
    try {
      return await _channel.invokeMethod<String>('takePendingPasteText', {
        'sessionId': sessionId,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> didPasteCaptureObserveChange(int sessionId) async {
    if (!_usesNativeCapture) return false;
    try {
      return await _channel.invokeMethod<bool>('didPasteCaptureObserveChange', {
            'sessionId': sessionId,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> readPasteText({int? sessionId}) async {
    if (sessionId != null) {
      final captured = await readCapturedPasteText(sessionId);
      if (captured != null) return captured;
    }
    return readSystemText();
  }

  Future<String?> readSystemText() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      return null;
    }
  }

  bool get _usesNativeCapture {
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows;
  }

  Future<void> _invokeVoid(String method, int sessionId) async {
    if (!_usesNativeCapture) return;
    try {
      await _channel.invokeMethod<void>(method, {'sessionId': sessionId});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
