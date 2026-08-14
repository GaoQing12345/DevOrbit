import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import 'json_clipboard_reader.dart';
import 'json_focus_snapshot.dart';

class JsonFocusRestorer with WindowListener {
  JsonFocusRestorer(this.controller, this.editor) {
    controller.findInputFocusNode.addListener(_trackFocus);
    controller.replaceInputFocusNode.addListener(_trackFocus);
    editorFocusNode.addListener(_trackFocus);
    controller.findInputController.addListener(_trackContentChange);
    controller.replaceInputController.addListener(_trackContentChange);
    editor.addListener(_trackContentChange);
    _lifecycle = AppLifecycleListener(
      onInactive: _suspendFocus,
      onResume: _restoreFocus,
    );
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  static const _clipboardSettleDelay = Duration(milliseconds: 140);
  static const _clipboardSessionLimit = Duration(seconds: 5);

  final CodeFindController controller;
  final CodeLineEditingController editor;
  final _clipboardReader = const JsonClipboardReader();
  final editorFocusNode = FocusNode(debugLabel: 'JSON editor');
  late final AppLifecycleListener _lifecycle;
  JsonFocusTarget? _lastTarget;
  JsonFocusSnapshot? _snapshot;
  Timer? _clipboardTimer;
  bool _pasteFallbackArmed = false;
  bool _disposed = false;
  bool _active = true;

  set active(bool value) {
    _active = value;
    if (!value) _cancelRestore();
  }

  void _trackFocus() {
    final target = _focusedJsonTarget();
    if (target == null) return;
    _lastTarget = target;
  }

  void _trackContentChange() {
    final snapshot = _snapshot;
    if (snapshot != null && !_contentMatches(snapshot)) {
      _cancelRestore();
    }
  }

  JsonFocusTarget? _focusedJsonTarget() {
    if (controller.findInputFocusNode.hasFocus) return JsonFocusTarget.find;
    if (controller.replaceInputFocusNode.hasFocus) {
      return JsonFocusTarget.replace;
    }
    if (editorFocusNode.hasFocus) return JsonFocusTarget.editor;
    return null;
  }

  void _suspendFocus() {
    if (!_active || _hasExternalEditableFocus()) return;
    final snapshot =
        _snapshot ?? _captureSnapshot(_focusedJsonTarget() ?? _lastTarget);
    if (snapshot == null) return;
    _snapshot = snapshot;
    _pasteFallbackArmed = true;
    unawaited(_clipboardReader.armPasteCapture());
  }

  JsonFocusSnapshot? _captureSnapshot(JsonFocusTarget? target) {
    if (target == null || !target.isAvailable(controller)) return null;
    final input = target.input(controller);
    return JsonFocusSnapshot(
      target: target,
      content: target == JsonFocusTarget.editor ? editor.text : input!.text,
      clipboardBefore: _clipboardReader.read(),
      suspendedAt: DateTime.now(),
      editorSelection: target == JsonFocusTarget.editor
          ? editor.selection
          : null,
      inputSelection: input?.selection,
    );
  }

  void _restoreFocus() {
    if (!_active) return _cancelRestore();
    final snapshot = _snapshot;
    if (snapshot == null) {
      _pasteFallbackArmed = false;
      return;
    }
    _restoreSelection(snapshot);
    _requestFocus(snapshot.target);
    _clipboardTimer?.cancel();
    _clipboardTimer = Timer(
      _clipboardSettleDelay,
      () => unawaited(_pasteChangedClipboard(snapshot)),
    );
  }

  void _restoreSelection(JsonFocusSnapshot snapshot) {
    if (!_contentMatches(snapshot)) return;
    if (snapshot.target == JsonFocusTarget.editor) {
      editor.selection = snapshot.editorSelection!;
    } else {
      snapshot.target.input(controller)!.selection = snapshot.inputSelection!;
    }
  }

  Future<void> _pasteChangedClipboard(JsonFocusSnapshot snapshot) async {
    final clipboardBefore = await snapshot.clipboardBefore;
    final clipboardNow = await _clipboardReader.read();
    if (!_canAutoPaste(snapshot)) return;
    if (!clipboardNow.hasChangedSince(clipboardBefore)) {
      return _cancelRestore();
    }
    final text = await _clipboardReader.readPasteText();
    if (!_canAutoPaste(snapshot)) return;
    if (text == null || text.isEmpty) return _cancelRestore();
    _pasteText(snapshot, text);
  }

  bool _canAutoPaste(JsonFocusSnapshot snapshot) {
    if (_disposed || !_active || !identical(_snapshot, snapshot)) return false;
    if (DateTime.now().difference(snapshot.suspendedAt) >
        _clipboardSessionLimit) {
      _cancelRestore();
      return false;
    }
    if (!snapshot.target.hasFocus(controller, editorFocusNode) ||
        !_contentMatches(snapshot)) {
      _cancelRestore();
      return false;
    }
    if (_hasExternalEditableFocus()) {
      _cancelRestore();
      return false;
    }
    return true;
  }

  bool _contentMatches(JsonFocusSnapshot snapshot) {
    final current = snapshot.target == JsonFocusTarget.editor
        ? editor.text
        : snapshot.target.input(controller)?.text;
    return current == snapshot.content;
  }

  void _requestFocus(JsonFocusTarget target) {
    switch (target) {
      case JsonFocusTarget.editor:
        editorFocusNode.requestFocus();
      case JsonFocusTarget.find:
        if (controller.value == null) return _cancelRestore();
        controller.findInputFocusNode.requestFocus();
      case JsonFocusTarget.replace:
        if (controller.value == null) return _cancelRestore();
        controller.replaceInputFocusNode.requestFocus();
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_active || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyV) return false;
    final keyboard = HardwareKeyboard.instance;
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    if (!isMacOS && keyboard.isMetaPressed) return _handleWindowsClipboard();
    if (!_pasteFallbackArmed) return false;
    if (isMacOS ? !keyboard.isMetaPressed : !keyboard.isControlPressed) {
      return false;
    }
    final snapshot = _snapshot;
    if (snapshot == null ||
        snapshot.target.hasFocus(controller, editorFocusNode)) {
      return false;
    }
    if (_hasExternalEditableFocus()) {
      _cancelRestore();
      return false;
    }
    _pasteFallbackArmed = false;
    unawaited(_pasteClipboard(snapshot));
    return true;
  }

  void pasteFocusedTarget() {
    final snapshot = _snapshot;
    if (_pasteFallbackArmed &&
        snapshot != null &&
        snapshot.target.hasFocus(controller, editorFocusNode)) {
      _pasteFallbackArmed = false;
      unawaited(_pasteClipboard(snapshot));
      return;
    }
    final target = _focusedJsonTarget();
    if (target != null) unawaited(_pasteCurrentSelection(target));
  }

  bool _handleWindowsClipboard() {
    if (_hasExternalEditableFocus()) {
      _cancelRestore();
    } else {
      _suspendFocus();
    }
    return false;
  }

  Future<void> _pasteClipboard(JsonFocusSnapshot snapshot) async {
    final text = await _clipboardReader.readPasteText();
    if (_disposed || !identical(_snapshot, snapshot)) return;
    if (text == null || text.isEmpty) return;
    _pasteText(snapshot, text);
  }

  Future<void> _pasteCurrentSelection(JsonFocusTarget target) async {
    final editorSelection = target == JsonFocusTarget.editor
        ? editor.selection
        : null;
    final input = target.input(controller);
    final inputSelection = input?.selection;
    final text = await _clipboardReader.readPasteText();
    if (_disposed || text == null || text.isEmpty) return;
    if (!target.hasFocus(controller, editorFocusNode)) return;
    if (target == JsonFocusTarget.editor) {
      editor.replaceSelection(text, editorSelection);
    } else {
      replaceTextSelectionAt(input!, text, inputSelection!);
    }
    _requestFocus(target);
  }

  void _pasteText(JsonFocusSnapshot snapshot, String text) {
    if (snapshot.target == JsonFocusTarget.editor) {
      editor.replaceSelection(text, snapshot.editorSelection);
    } else {
      replaceTextSelectionAt(
        snapshot.target.input(controller)!,
        text,
        snapshot.inputSelection!,
      );
    }
    _requestFocus(snapshot.target);
    _cancelRestore();
  }

  bool _hasExternalEditableFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || _isJsonFocus(focus)) return false;
    return focus.context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _isJsonFocus(FocusNode focus) {
    return JsonFocusTarget.values.any(
      (target) => target.ownsFocus(focus, controller, editorFocusNode),
    );
  }

  void _cancelRestore() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    _snapshot = null;
    _pasteFallbackArmed = false;
    unawaited(_clipboardReader.discardPendingPasteText());
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
    controller.findInputController.removeListener(_trackContentChange);
    controller.replaceInputController.removeListener(_trackContentChange);
    editor.removeListener(_trackContentChange);
    _clipboardTimer?.cancel();
    _lifecycle.dispose();
    editorFocusNode.dispose();
  }
}
