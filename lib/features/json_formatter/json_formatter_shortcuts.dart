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

Map<Type, Action<Intent>> buildJsonEditorActions({
  required VoidCallback onPaste,
}) {
  return {
    CodeShortcutPasteIntent: CallbackAction<CodeShortcutPasteIntent>(
      onInvoke: (_) => onPaste(),
    ),
  };
}

/// Formatter-wide shortcuts.
///
/// On macOS and Windows the editor is a WebView that owns the keyboard, so the
/// same set is handled there in the DOM and forwarded through `onCommand`.
/// These bindings keep the Flutter code editor path (and the tests) in parity.
Map<ShortcutActivator, VoidCallback> buildJsonFormatterShortcuts({
  required VoidCallback onFind,
  required VoidCallback onReplace,
  VoidCallback? onSave,
  VoidCallback? onFormat,
  VoidCallback? onCompact,
  VoidCallback? onSort,
  VoidCallback? onGoToLine,
}) {
  final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
  final shortcuts = <ShortcutActivator, VoidCallback>{
    SingleActivator(LogicalKeyboardKey.keyF, meta: isMacOS, control: !isMacOS):
        onFind,
    SingleActivator(
      isMacOS ? LogicalKeyboardKey.keyR : LogicalKeyboardKey.keyH,
      meta: isMacOS,
      control: !isMacOS,
    ): onReplace,
  };
  void bind(
    LogicalKeyboardKey key, {
    bool shift = false,
    required VoidCallback? action,
  }) {
    if (action == null) return;
    shortcuts[SingleActivator(
          key,
          meta: isMacOS,
          control: !isMacOS,
          shift: shift,
        )] =
        action;
  }

  bind(LogicalKeyboardKey.keyS, action: onSave);
  bind(LogicalKeyboardKey.keyS, shift: true, action: onSort);
  bind(LogicalKeyboardKey.keyF, shift: true, action: onFormat);
  bind(LogicalKeyboardKey.keyM, shift: true, action: onCompact);
  bind(LogicalKeyboardKey.keyG, action: onGoToLine);
  return shortcuts;
}
