import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

enum _JsonFocusTarget { editor, find, replace }

class JsonFocusRestorer {
  JsonFocusRestorer({required this.controller}) {
    controller.findInputFocusNode.addListener(_trackFocus);
    controller.replaceInputFocusNode.addListener(_trackFocus);
    editorFocusNode.addListener(_trackFocus);
    _lifecycle = AppLifecycleListener(
      onInactive: _rememberFocus,
      onResume: _restoreFocus,
    );
  }

  final CodeFindController controller;
  final editorFocusNode = FocusNode(debugLabel: 'JSON editor');
  late final AppLifecycleListener _lifecycle;
  _JsonFocusTarget? _lastTarget;
  _JsonFocusTarget? _resumeTarget;

  void _trackFocus() {
    if (controller.findInputFocusNode.hasFocus) {
      _lastTarget = _JsonFocusTarget.find;
    } else if (controller.replaceInputFocusNode.hasFocus) {
      _lastTarget = _JsonFocusTarget.replace;
    } else if (editorFocusNode.hasFocus) {
      _lastTarget = _JsonFocusTarget.editor;
    }
  }

  void _rememberFocus() {
    final target = _lastTarget;
    _resumeTarget = switch (target) {
      _JsonFocusTarget.find ||
      _JsonFocusTarget.replace when controller.value == null => null,
      _ => target,
    };
  }

  void _restoreFocus() {
    final target = _resumeTarget;
    if (target == null) return;
    _resumeTarget = null;
    switch (target) {
      case _JsonFocusTarget.editor:
        editorFocusNode.requestFocus();
      case _JsonFocusTarget.find:
        if (controller.value == null) return;
        controller.findInputFocusNode.requestFocus();
      case _JsonFocusTarget.replace:
        if (controller.value == null) return;
        controller.replaceInputFocusNode.requestFocus();
    }
  }

  void dispose() {
    controller.findInputFocusNode.removeListener(_trackFocus);
    controller.replaceInputFocusNode.removeListener(_trackFocus);
    editorFocusNode.removeListener(_trackFocus);
    _lifecycle.dispose();
    editorFocusNode.dispose();
  }
}
