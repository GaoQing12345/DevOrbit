import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_clipboard_diagnostics.dart';

class DesktopPasteRequest {
  const DesktopPasteRequest({this.sessionId, this.text});

  final int? sessionId;
  final String? text;
}

enum DesktopPasteCaptureState { unavailable, armed, prearmed }

class DesktopClipboardReader {
  const DesktopClipboardReader();

  static const _channel = MethodChannel('dev_orbit/clipboard');
  static final _pasteRequests = StreamController<DesktopPasteRequest>.broadcast(
    sync: true,
  );
  static bool _pasteRequestHandlerInstalled = false;

  Stream<DesktopPasteRequest> get pasteRequests {
    _installPasteRequestHandler();
    return _pasteRequests.stream;
  }

  Future<void> registerPasteTarget() {
    if (!_usesNativeCapture) {
      return Future<void>.value();
    }
    return _invokeVoid('registerPasteTarget');
  }

  Future<void> unregisterPasteTarget() {
    if (!_usesNativeCapture) {
      return Future<void>.value();
    }
    return _invokeVoid('unregisterPasteTarget');
  }

  Future<DesktopPasteCaptureState> armPasteCapture(int sessionId) async {
    if (!_usesNativeCapture) {
      DesktopClipboardDiagnostics.write('arm_skip', {'session': sessionId});
      return DesktopPasteCaptureState.unavailable;
    }
    DesktopClipboardDiagnostics.write('arm_start', {'session': sessionId});
    try {
      final supported =
          await _channel.invokeMethod<bool>('supportsPasteCapture') ?? false;
      DesktopClipboardDiagnostics.write('arm_supports', {
        'session': sessionId,
        'supported': supported,
      });
      if (!supported) return DesktopPasteCaptureState.unavailable;
      final prearmed =
          await _channel.invokeMethod<bool>('armPasteCapture', {
            'sessionId': sessionId,
          }) ??
          false;
      DesktopClipboardDiagnostics.write('arm_success', {
        'session': sessionId,
        'prearmed': prearmed,
      });
      return prearmed
          ? DesktopPasteCaptureState.prearmed
          : DesktopPasteCaptureState.armed;
    } on MissingPluginException {
      DesktopClipboardDiagnostics.write('arm_error', {
        'session': sessionId,
        'type': 'missing_plugin',
      });
      return DesktopPasteCaptureState.unavailable;
    } on PlatformException catch (error) {
      DesktopClipboardDiagnostics.write('arm_error', {
        'session': sessionId,
        'type': error.code,
        'message': error.message,
      });
      return DesktopPasteCaptureState.unavailable;
    }
  }

  Future<void> discardPendingPasteText(int sessionId) {
    return _invokeVoid('discardPendingPasteText', sessionId: sessionId);
  }

  Future<String?> readCapturedPasteText(int sessionId) async {
    if (!_usesNativeCapture) return null;
    try {
      final text = await _channel.invokeMethod<String>('takePendingPasteText', {
        'sessionId': sessionId,
      });
      DesktopClipboardDiagnostics.write('capture_read', {
        'session': sessionId,
        'available': text != null,
        'length': text?.length,
      });
      return text;
    } on MissingPluginException {
      DesktopClipboardDiagnostics.write('capture_read_error', {
        'session': sessionId,
        'type': 'missing_plugin',
      });
      return null;
    } on PlatformException catch (error) {
      DesktopClipboardDiagnostics.write('capture_read_error', {
        'session': sessionId,
        'type': error.code,
        'message': error.message,
      });
      return null;
    }
  }

  Future<bool> didPasteCaptureObserveChange(int sessionId) async {
    if (!_usesNativeCapture) return false;
    try {
      final observed =
          await _channel.invokeMethod<bool>('didPasteCaptureObserveChange', {
            'sessionId': sessionId,
          }) ??
          false;
      DesktopClipboardDiagnostics.write('capture_observed', {
        'session': sessionId,
        'observed': observed,
      });
      return observed;
    } on MissingPluginException {
      DesktopClipboardDiagnostics.write('capture_observed_error', {
        'session': sessionId,
        'type': 'missing_plugin',
      });
      return false;
    } on PlatformException catch (error) {
      DesktopClipboardDiagnostics.write('capture_observed_error', {
        'session': sessionId,
        'type': error.code,
        'message': error.message,
      });
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
    // Windows clipboard providers may keep the clipboard open briefly while
    // they publish several formats (or restore the previous value after a
    // synthetic paste). A single Clipboard.getData call is therefore not
    // reliable enough for desktop tools. Retry both null results and transient
    // platform failures, but keep the first successful value unchanged.
    // On macOS the native paste monitor already captures iCopy's synthetic
    // Command+V synchronously. Retrying a normal system read here only keeps
    // the paste operation alive for roughly half a second and makes a small
    // pasteboard race visible as UI lag. The retry sequence is needed for
    // Windows clipboard providers, which publish the selected item in stages.
    final retryDelays = defaultTargetPlatform == TargetPlatform.windows
        ? const [
            Duration.zero,
            Duration(milliseconds: 8),
            Duration(milliseconds: 16),
            Duration(milliseconds: 32),
            Duration(milliseconds: 64),
            Duration(milliseconds: 128),
            Duration(milliseconds: 256),
          ]
        : const [Duration.zero];
    for (final delay in retryDelays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      try {
        final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
        DesktopClipboardDiagnostics.write('system_read', {
          'delay_ms': delay.inMilliseconds,
          'available': text != null,
          'length': text?.length,
        });
        if (text != null) return text;
      } on PlatformException catch (error) {
        DesktopClipboardDiagnostics.write('system_read_error', {
          'delay_ms': delay.inMilliseconds,
          'type': error.code,
          'message': error.message,
        });
        // The clipboard can be temporarily owned by another process. Continue
        // with the next attempt instead of turning a timing race into a paste
        // failure.
      }
    }
    return null;
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
      if (arguments is! Map) {
        DesktopClipboardDiagnostics.write('native_request_invalid');
        return;
      }
      final sessionId = arguments['sessionId'];
      final text = arguments['text'];
      final source = arguments['source'];
      if (sessionId is! int && text is! String) {
        DesktopClipboardDiagnostics.write('native_request_invalid_fields');
        return;
      }
      DesktopClipboardDiagnostics.write('native_request', {
        'session': sessionId,
        'has_text': text is String,
        'length': text is String ? text.length : null,
        'source': source is String ? source : null,
      });
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
      DesktopClipboardDiagnostics.write('channel_success', {
        'method': method,
        'session': sessionId,
      });
    } on MissingPluginException {
      DesktopClipboardDiagnostics.write('channel_error', {
        'method': method,
        'session': sessionId,
        'type': 'missing_plugin',
      });
      return;
    } on PlatformException catch (error) {
      DesktopClipboardDiagnostics.write('channel_error', {
        'method': method,
        'session': sessionId,
        'type': error.code,
        'message': error.message,
      });
      return;
    }
  }
}
