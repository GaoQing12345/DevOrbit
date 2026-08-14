import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../core/desktop/desktop_clipboard_focus_restorer.dart';

class JsonFocusRestorer {
  JsonFocusRestorer(this.controller, this.editor)
    : editorFocusNode = FocusNode(debugLabel: 'JSON editor') {
    _restorer = DesktopClipboardFocusRestorer(
      targets: [
        CodeLineClipboardTarget(controller: editor, focusNode: editorFocusNode),
        TextEditingClipboardTarget(
          controller: controller.findInputController,
          focusNode: controller.findInputFocusNode,
          available: () => controller.value != null,
        ),
        TextEditingClipboardTarget(
          controller: controller.replaceInputController,
          focusNode: controller.replaceInputFocusNode,
          available: () => controller.value != null,
        ),
      ],
    );
  }

  final CodeFindController controller;
  final CodeLineEditingController editor;
  final FocusNode editorFocusNode;
  late final DesktopClipboardFocusRestorer _restorer;

  set active(bool value) => _restorer.active = value;

  void pasteFocusedTarget() => _restorer.pasteFocusedTarget();

  void dispose() {
    _restorer.dispose();
    editorFocusNode.dispose();
  }
}
