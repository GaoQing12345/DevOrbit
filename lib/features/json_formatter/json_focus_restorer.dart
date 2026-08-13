import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

enum _JsonFocusTarget { editor, find, replace }

class JsonFocusRestorer with WindowListener {
  JsonFocusRestorer(this.controller, this.editor) {
    controller.findInputFocusNode.addListener(_trackFocus);
    controller.replaceInputFocusNode.addListener(_trackFocus);
    editorFocusNode.addListener(_trackFocus);
    _lifecycle = AppLifecycleListener(
      onInactive: _suspendFocus,
      onResume: _restoreFocus,
    );
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  final CodeFindController controller;
  final CodeLineEditingController editor;
  final editorFocusNode = FocusNode(debugLabel: 'JSON editor');
  late final AppLifecycleListener _lifecycle;
  _JsonFocusTarget? _lastTarget;
  _JsonFocusTarget? _resumeTarget;
  bool _pasteFallbackArmed = false;
  bool _disposed = false;
  bool _active = true;

  set active(bool value) {
    _active = value;
    if (!value) _cancelRestore();
  }

  void _trackFocus() {
    final _JsonFocusTarget? target;
    if (controller.findInputFocusNode.hasFocus) {
      target = _JsonFocusTarget.find;
    } else if (controller.replaceInputFocusNode.hasFocus) {
      target = _JsonFocusTarget.replace;
    } else if (editorFocusNode.hasFocus) {
      target = _JsonFocusTarget.editor;
    } else {
      return;
    }
    _lastTarget = target;
    if (_resumeTarget == target) {
      _resumeTarget = null;
      _pasteFallbackArmed = false;
    }
  }

  void _suspendFocus() {
    if (!_active) return;
    _pasteFallbackArmed = true;
    _rememberFocus();
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
    if (!_active) return _cancelRestore();
    final target = _resumeTarget;
    if (target == null) {
      _pasteFallbackArmed = false;
      return;
    }
    _requestFocus(target);
  }

  void _requestFocus(_JsonFocusTarget target) {
    switch (target) {
      case _JsonFocusTarget.editor:
        editorFocusNode.requestFocus();
      case _JsonFocusTarget.find:
        if (controller.value == null) return _cancelRestore();
        controller.findInputFocusNode.requestFocus();
      case _JsonFocusTarget.replace:
        if (controller.value == null) return _cancelRestore();
        controller.replaceInputFocusNode.requestFocus();
    }
  }

  void _cancelRestore() {
    _resumeTarget = null;
    _pasteFallbackArmed = false;
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_active) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyV) return false;
    final keyboard = HardwareKeyboard.instance;
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    if (!isMacOS && keyboard.isMetaPressed) {
      if (_hasExternalEditableFocus()) {
        _cancelRestore();
      } else {
        _suspendFocus();
      }
      return false;
    }
    if (!_pasteFallbackArmed) return false;
    if (isMacOS ? !keyboard.isMetaPressed : !keyboard.isControlPressed) {
      return false;
    }
    final target = _resumeTarget;
    if (target == null || _targetHasFocus(target)) return false;
    if (_hasExternalEditableFocus()) {
      _cancelRestore();
      return false;
    }
    if (!_targetIsAvailable(target)) return false;
    _pasteFallbackArmed = false;
    unawaited(_pasteClipboard(target));
    return true;
  }

  bool _hasExternalEditableFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || _isJsonFocus(focus)) return false;
    return focus.context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _isJsonFocus(FocusNode focus) {
    return focus == editorFocusNode ||
        focus == controller.findInputFocusNode ||
        focus == controller.replaceInputFocusNode;
  }

  bool _targetIsAvailable(_JsonFocusTarget target) {
    if (target == _JsonFocusTarget.editor) return true;
    return controller.value != null;
  }

  bool _targetHasFocus(_JsonFocusTarget target) => switch (target) {
    _JsonFocusTarget.editor => editorFocusNode.hasFocus,
    _JsonFocusTarget.find => controller.findInputFocusNode.hasFocus,
    _JsonFocusTarget.replace => controller.replaceInputFocusNode.hasFocus,
  };

  Future<void> _pasteClipboard(_JsonFocusTarget target) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (_disposed) return;
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    switch (target) {
      case _JsonFocusTarget.editor:
        editor.replaceSelection(text);
      case _JsonFocusTarget.find:
        _replaceTextSelection(controller.findInputController, text);
      case _JsonFocusTarget.replace:
        _replaceTextSelection(controller.replaceInputController, text);
    }
    _requestFocus(target);
  }

  void _replaceTextSelection(TextEditingController input, String text) {
    final selection = input.selection;
    final start = _validOffset(selection.start, input.text.length);
    final end = _validOffset(selection.end, input.text.length);
    final nextText = input.text.replaceRange(start, end, text);
    input.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  int _validOffset(int offset, int textLength) {
    if (offset < 0 || offset > textLength) return textLength;
    return offset;
  }

  @override
  void onWindowBlur() => _suspendFocus();

  @override
  void onWindowFocus() => _restoreFocus();

  void dispose() {
    _disposed = true;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    windowManager.removeListener(this);
    controller.findInputFocusNode.removeListener(_trackFocus);
    controller.replaceInputFocusNode.removeListener(_trackFocus);
    editorFocusNode.removeListener(_trackFocus);
    _lifecycle.dispose();
    editorFocusNode.dispose();
  }
}
