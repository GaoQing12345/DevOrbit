import 'package:flutter/services.dart';

import 'json_document_controller.dart';

typedef ClipboardReader = Future<ClipboardData?> Function();

Future<bool> importInitialClipboardJson({
  required JsonDocumentController controller,
  required int indentSize,
  required ClipboardReader readClipboard,
}) async {
  try {
    final data = await readClipboard();
    return controller.importClipboard(data?.text ?? '', indentSize);
  } on PlatformException {
    return false;
  }
}
