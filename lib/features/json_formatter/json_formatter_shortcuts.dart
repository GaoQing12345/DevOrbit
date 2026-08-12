import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Map<ShortcutActivator, VoidCallback> buildJsonFormatterShortcuts({
  required VoidCallback onFind,
  required VoidCallback onReplace,
}) {
  final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
  return {
    SingleActivator(LogicalKeyboardKey.keyF, meta: isMacOS, control: !isMacOS):
        onFind,
    SingleActivator(
      isMacOS ? LogicalKeyboardKey.keyR : LogicalKeyboardKey.keyH,
      meta: isMacOS,
      control: !isMacOS,
    ): onReplace,
  };
}
