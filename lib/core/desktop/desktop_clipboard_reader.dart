import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopPasteRequest {
  const DesktopPasteRequest({this.sessionId, this.text});

  final int? sessionId;
  final String? text;
}

class DesktopClipboardReader {
  const DesktopClipboardReader();

  static const _channel = MethodChannel('dev_orbit/clipboard');
  static final _pasteRequests =
      StreamController<DesktopPasteRequest>.broadcast(sync: true);
  static bool _pasteRequestHandlerInstalled = false;

  Stream<DesktopPasteRequest> get pasteRequests {
    _installPasteRequestHandler();
    return _pasteRequests.stream;
  }

  Future<void> registerPasteTarget() {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return Future<void>.value();
    }
    return _invokeVoid('registerPasteTarget');
  }

  Future<void> unregisterPasteTarget() {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return Future<void>.value();
    }
    return _invokeVoid('unregisterPasteTarget');
  }

  Future<void> armPasteCapture(int sessionId) {
    return _invokeVoid('armPasteCapture', sessionId: sessionId);
  }

  Future<void> discardPendingPasteText(int sessionId) {
    return _invokeVoid('discardPendingPasteText', sessionId: sessionId);
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

  static void _installPasteRequestHandler() {
    if (_pasteRequestHandlerInstalled) return;
    _pasteRequestHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'pasteRequested') return;
      final arguments = call.arguments;
      if (arguments is! Map) return;
      final sessionId = arguments['sessionId'];
      final text = arguments['text'];
      if (sessionId is! int && text is! String) return;
      _pasteRequests.add(
        DesktopPasteRequest(
          sessionId: sessionId is int ? sessionId : null,
          text: text is String ? text : null,
        ),
      );
    });
  }

  Future<void> _invokeVoid(String method, {int? sessionId}) async {
    if (!_usesNativeCapture) return;
    try {
      await _channel.invokeMethod<void>(
        method,
        sessionId == null ? null : {'sessionId': sessionId},
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
