import 'package:flutter/services.dart';

import 'sql_log_controller.dart';

typedef SqlLogClipboardReader = Future<ClipboardData?> Function();

Future<bool> importSqlLogClipboard({
  required SqlLogController controller,
  required SqlLogClipboardReader readClipboard,
}) async {
  try {
    final text = (await readClipboard())?.text;
    return text != null && controller.importRecognizedLog(text);
  } on PlatformException {
    return false;
  }
}
