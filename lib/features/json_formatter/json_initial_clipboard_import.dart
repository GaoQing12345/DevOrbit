import 'dart:async';

import 'package:flutter/services.dart';

import 'json_document_controller.dart';

typedef ClipboardReader = Future<ClipboardData?> Function();

Future<bool> importInitialClipboardJson({
  required JsonDocumentController controller,
  required int indentSize,
  required ClipboardReader readClipboard,
}) async {
  // Opening a standalone JSON window often coincides with a clipboard tool
  // finishing its restore animation. Treat a temporarily unavailable/null
  // clipboard as a retryable condition instead of losing the initial import.
  for (final delay in const [
    Duration.zero,
    Duration(milliseconds: 8),
    Duration(milliseconds: 16),
    Duration(milliseconds: 32),
    Duration(milliseconds: 64),
    Duration(milliseconds: 128),
    Duration(milliseconds: 256),
  ]) {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    try {
      final data = await readClipboard();
      if (data == null) continue;
      return await controller.importClipboard(data.text ?? '', indentSize);
    } on PlatformException {
      // Continue while another desktop process owns the clipboard.
    }
  }
  return false;
}
