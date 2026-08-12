import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

class JsonEditorShortcutsBuilder extends CodeShortcutsActivatorsBuilder {
  const JsonEditorShortcutsBuilder();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    if (type == CodeShortcutType.paste) {
      return defaultTargetPlatform == TargetPlatform.macOS
          ? const [SingleActivator(LogicalKeyboardKey.keyV, meta: true)]
          : const [SingleActivator(LogicalKeyboardKey.keyV, control: true)];
    }
    return const DefaultCodeShortcutsActivatorsBuilder().build(type);
  }
}

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
