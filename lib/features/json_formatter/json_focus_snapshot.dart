import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'json_clipboard_reader.dart';

enum JsonFocusTarget { editor, find, replace }

extension JsonFocusTargetState on JsonFocusTarget {
  TextEditingController? input(CodeFindController controller) => switch (this) {
    JsonFocusTarget.editor => null,
    JsonFocusTarget.find => controller.findInputController,
    JsonFocusTarget.replace => controller.replaceInputController,
  };

  bool isAvailable(CodeFindController controller) {
    return this == JsonFocusTarget.editor || controller.value != null;
  }

  bool hasFocus(CodeFindController controller, FocusNode editorFocusNode) {
    return switch (this) {
      JsonFocusTarget.editor => editorFocusNode.hasFocus,
      JsonFocusTarget.find => controller.findInputFocusNode.hasFocus,
      JsonFocusTarget.replace => controller.replaceInputFocusNode.hasFocus,
    };
  }

  bool ownsFocus(
    FocusNode focus,
    CodeFindController controller,
    FocusNode editorFocusNode,
  ) {
    return switch (this) {
      JsonFocusTarget.editor => focus == editorFocusNode,
      JsonFocusTarget.find => focus == controller.findInputFocusNode,
      JsonFocusTarget.replace => focus == controller.replaceInputFocusNode,
    };
  }
}

void replaceTextSelectionAt(
  TextEditingController input,
  String text,
  TextSelection selection,
) {
  final start = selection.start.clamp(0, input.text.length);
  final end = selection.end.clamp(0, input.text.length);
  input.value = TextEditingValue(
    text: input.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

class JsonFocusSnapshot {
  const JsonFocusSnapshot({
    required this.target,
    required this.content,
    required this.clipboardBefore,
    required this.suspendedAt,
    this.editorSelection,
    this.inputSelection,
  });

  final JsonFocusTarget target;
  final String content;
  final Future<JsonClipboardState> clipboardBefore;
  final DateTime suspendedAt;
  final CodeLineSelection? editorSelection;
  final TextSelection? inputSelection;
}
