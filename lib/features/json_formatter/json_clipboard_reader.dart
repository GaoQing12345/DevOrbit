import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class JsonClipboardState {
  const JsonClipboardState({required this.text, required this.revision});

  final String? text;
  final int? revision;

  bool hasChangedSince(JsonClipboardState previous) {
    final previousRevision = previous.revision;
    if (revision != null && previousRevision != null) {
      return revision != previousRevision;
    }
    return text != null && previous.text != null && text != previous.text;
  }
}

class JsonClipboardReader {
  const JsonClipboardReader();

  static const _channel = MethodChannel('dev_orbit/clipboard');

  Future<String?> readText() => _readText();

  Future<String?> readPasteText() async {
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.macOS &&
        platform != TargetPlatform.windows) {
      return _readText();
    }
    final pending = await _takePendingPasteText();
    if (pending != null && pending.isNotEmpty) return pending;
    return _readText();
  }

  Future<JsonClipboardState> read() async {
    final textFuture = _readText();
    final revisionFuture = _readRevision();
    return JsonClipboardState(
      text: await textFuture,
      revision: await revisionFuture,
    );
  }

  Future<String?> _readText() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      return null;
    }
  }

  Future<int?> _readRevision() async {
    try {
      return await _channel.invokeMethod<int>('getChangeCount');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<String?> _takePendingPasteText() async {
    try {
      return await _channel.invokeMethod<String>('takePendingPasteText');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
