import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_clipboard_reader.dart';

abstract class DesktopClipboardTarget {
  FocusNode get focusNode;
  Listenable get contentListenable;
  bool get isAvailable;
  String get text;
  Object get selection;

  void restoreSelection(Object selection);
  void replaceSelection(String text, Object selection);
}

class TextEditingClipboardTarget implements DesktopClipboardTarget {
  TextEditingClipboardTarget({
    required this.controller,
    required this.focusNode,
    this.available = _alwaysAvailable,
    this.onChanged,
  });

  final TextEditingController controller;
  @override
  final FocusNode focusNode;
  final bool Function() available;
  final ValueChanged<String>? onChanged;

  @override
  Listenable get contentListenable => controller;

  @override
  bool get isAvailable => available();

  @override
  String get text => controller.text;

  @override
  Object get selection => controller.selection;

  @override
  void restoreSelection(Object selection) {
    controller.selection = selection as TextSelection;
  }

  @override
  void replaceSelection(String text, Object selection) {
    final current = controller.text;
    final selected = selection as TextSelection;
    final start = selected.start.clamp(0, current.length);
    final end = selected.end.clamp(0, current.length);
    final next = current.replaceRange(start, end, text);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    onChanged?.call(next);
  }

  static bool _alwaysAvailable() => true;
}

class CodeLineClipboardTarget implements DesktopClipboardTarget {
  CodeLineClipboardTarget({
    required this.controller,
    required this.focusNode,
    this.onChanged,
  });

  final CodeLineEditingController controller;
  @override
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;

  @override
  Listenable get contentListenable => controller;

  @override
  bool get isAvailable => true;

  @override
  String get text => controller.text;

  @override
  Object get selection => controller.selection;

  @override
  void restoreSelection(Object selection) {
    controller.selection = selection as CodeLineSelection;
  }

  @override
  void replaceSelection(String text, Object selection) {
    controller.replaceSelection(text, selection as CodeLineSelection);
    onChanged?.call(controller.text);
  }
}

class DesktopClipboardFocusRestorer with WindowListener {
  DesktopClipboardFocusRestorer({required List<DesktopClipboardTarget> targets})
    : _targets = List.unmodifiable(targets) {
    for (final target in _targets) {
      target.focusNode.addListener(_trackFocus);
      target.contentListenable.addListener(_trackContentChange);
    }
    _lifecycle = AppLifecycleListener(
      onInactive: _suspendFocus,
      onResume: _restoreFocus,
    );
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _capturedPasteSubscription = _clipboardReader.capturedPasteSessions.listen(
      _handleCapturedPasteSession,
    );
  }

  static const _clipboardSessionLimit = Duration(seconds: 30);
  static const _resumedCaptureLimit = Duration(seconds: 3);
  static const _captureRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 4),
    Duration(milliseconds: 8),
    Duration(milliseconds: 16),
    Duration(milliseconds: 32),
    Duration(milliseconds: 64),
  ];
  static int _nextSessionId = 0;

  final List<DesktopClipboardTarget> _targets;
  final _clipboardReader = const DesktopClipboardReader();
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<int> _capturedPasteSubscription;
  DesktopClipboardTarget? _lastTarget;
  _DesktopFocusSnapshot? _snapshot;
  bool _pasteFallbackArmed = false;
  bool _disposed = false;
  bool _active = true;
  int? _autoPasteSessionId;
  Timer? _captureRetryTimer;
  Timer? _resumedCaptureTimer;
  DesktopClipboardTarget? _suppressedPasteTarget;
  DateTime? _suppressPasteUntil;
  bool _skipNextPasteAction = false;

  set active(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) _cancelRestore();
  }

  void _trackFocus() {
    final target = _focusedTarget();
    if (target != null) _lastTarget = target;
  }

  void _trackContentChange() {
    final snapshot = _snapshot;
    if (snapshot != null && !_contentMatches(snapshot)) {
      _cancelRestore(expected: snapshot);
    }
  }

  DesktopClipboardTarget? _focusedTarget() {
    for (final target in _targets) {
      if (target.isAvailable && target.focusNode.hasFocus) return target;
    }
    return null;
  }

  void _suspendFocus() {
    if (!_active || _snapshot != null || _hasExternalEditableFocus()) return;
    final target = _focusedTarget() ?? _lastTarget;
    if (target == null || !target.isAvailable) return;
    final sessionId = ++_nextSessionId;
    _clearPasteSuppression();
    final snapshot = _DesktopFocusSnapshot(
      target: target,
      content: target.text,
      selection: target.selection,
      suspendedAt: DateTime.now(),
      sessionId: sessionId,
    );
    _snapshot = snapshot;
    _pasteFallbackArmed = true;
    _resumedCaptureTimer?.cancel();
    unawaited(_clipboardReader.armPasteCapture(sessionId));
  }

  void _restoreFocus() {
    if (!_active) {
      _cancelRestore();
      return;
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      _pasteFallbackArmed = false;
      return;
    }
    _restoreSelection(snapshot);
    _requestFocus(snapshot.target);
    _resumedCaptureTimer?.cancel();
    _resumedCaptureTimer = Timer(
      _resumedCaptureLimit,
      () => _cancelRestore(expected: snapshot),
    );
    if (_autoPasteSessionId == snapshot.sessionId) return;
    _autoPasteSessionId = snapshot.sessionId;
    unawaited(_pasteCapturedWhenReady(snapshot));
  }

  void _restoreSelection(_DesktopFocusSnapshot snapshot) {
    if (_contentMatches(snapshot) && snapshot.target.isAvailable) {
      snapshot.target.restoreSelection(snapshot.selection);
    }
  }

  Future<void> _pasteCapturedWhenReady(_DesktopFocusSnapshot snapshot) async {
    for (final delay in _captureRetryDelays) {
      if (delay != Duration.zero) await _waitForCaptureRetry(delay);
      if (!_canPaste(snapshot)) return;
      final text = await _clipboardReader.readCapturedPasteText(
        snapshot.sessionId,
      );
      if (!_canPaste(snapshot)) return;
      if (text != null) {
        if (text.isEmpty) {
          _cancelRestore(expected: snapshot);
        } else {
          _pasteText(snapshot, text, suppressFollowUpPaste: true);
        }
        return;
      }
    }
    // Native capture sends pasteTextCaptured when a delayed clipboard provider
    // finally publishes text. Keep this session alive instead of treating the
    // short compatibility poll as the lifetime of the paste operation.
    if (defaultTargetPlatform != TargetPlatform.windows) {
      _cancelRestore(expected: snapshot);
    }
  }

  void _handleCapturedPasteSession(int sessionId) {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.sessionId != sessionId) return;
    unawaited(_pasteCapturedSession(snapshot));
  }

  Future<void> _pasteCapturedSession(_DesktopFocusSnapshot snapshot) async {
    if (!_canPaste(snapshot)) return;
    final text = await _clipboardReader.readCapturedPasteText(
      snapshot.sessionId,
    );
    if (!_canPaste(snapshot) || text == null) return;
    if (text.isEmpty) {
      _cancelRestore(expected: snapshot);
      return;
    }
    _pasteText(snapshot, text, suppressFollowUpPaste: true);
  }

  bool _canPaste(_DesktopFocusSnapshot snapshot) {
    if (_disposed || !_active || !identical(_snapshot, snapshot)) return false;
    if (DateTime.now().difference(snapshot.suspendedAt) >
        _clipboardSessionLimit) {
      _cancelRestore(expected: snapshot);
      return false;
    }
    if (!snapshot.target.isAvailable || !_contentMatches(snapshot)) {
      _cancelRestore(expected: snapshot);
      return false;
    }
    if (_hasExternalEditableFocus()) {
      _cancelRestore(expected: snapshot);
      return false;
    }
    return true;
  }

  bool _contentMatches(_DesktopFocusSnapshot snapshot) {
    return snapshot.target.text == snapshot.content;
  }

  void _requestFocus(DesktopClipboardTarget target) {
    if (!target.isAvailable) {
      _cancelRestore();
      return;
    }
    target.focusNode.requestFocus();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_active || event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final isV = event.logicalKey == LogicalKeyboardKey.keyV;
    if (!isMacOS && isV && keyboard.isMetaPressed) {
      if (_hasExternalEditableFocus()) {
        _cancelRestore();
      } else {
        _suspendFocus();
      }
      return false;
    }
    final isPasteShortcut = isMacOS
        ? isV && keyboard.isMetaPressed
        : (isV && keyboard.isControlPressed) ||
              (event.logicalKey == LogicalKeyboardKey.insert &&
                  keyboard.isShiftPressed);
    if (!isPasteShortcut) {
      return false;
    }
    if (_consumePasteSuppression()) {
      _suppressMatchingPasteAction();
      return true;
    }
    final snapshot = _snapshot;
    if (!_pasteFallbackArmed || snapshot == null) return false;
    if (_hasExternalEditableFocus()) {
      _cancelRestore(expected: snapshot);
      return false;
    }
    _pasteFallbackArmed = false;
    _restoreSelection(snapshot);
    _requestFocus(snapshot.target);
    _suppressMatchingPasteAction();
    unawaited(_pasteExplicitClipboard(snapshot));
    return true;
  }

  void pasteFocusedTarget() {
    if (_skipNextPasteAction) {
      _skipNextPasteAction = false;
      return;
    }
    if (_consumePasteSuppression()) return;
    final snapshot = _snapshot;
    if (_pasteFallbackArmed && snapshot != null && _canPaste(snapshot)) {
      _pasteFallbackArmed = false;
      unawaited(_pasteExplicitClipboard(snapshot));
      return;
    }
    final target = _focusedTarget();
    if (target != null) unawaited(_pasteCurrentSelection(target));
  }

  Future<void> _pasteExplicitClipboard(_DesktopFocusSnapshot snapshot) async {
    var text = await _clipboardReader.readCapturedPasteText(snapshot.sessionId);
    if (text == null &&
        await _clipboardReader.didPasteCaptureObserveChange(
          snapshot.sessionId,
        )) {
      for (final delay in const [
        Duration(milliseconds: 4),
        Duration(milliseconds: 8),
        Duration(milliseconds: 16),
        Duration(milliseconds: 32),
      ]) {
        await _waitForCaptureRetry(delay);
        if (!_canPaste(snapshot)) return;
        text = await _clipboardReader.readCapturedPasteText(snapshot.sessionId);
        if (text != null) break;
      }
      if (text == null) {
        _cancelRestore(expected: snapshot);
        return;
      }
    }
    text ??= await _clipboardReader.readSystemText();
    if (!_canPaste(snapshot) || text == null || text.isEmpty) return;
    _pasteText(snapshot, text);
  }

  Future<void> _pasteCurrentSelection(DesktopClipboardTarget target) async {
    final selection = target.selection;
    final text = await _clipboardReader.readSystemText();
    if (_disposed || text == null || text.isEmpty) return;
    if (!target.isAvailable || !target.focusNode.hasFocus) return;
    target.replaceSelection(text, selection);
    _requestFocus(target);
  }

  void _pasteText(
    _DesktopFocusSnapshot snapshot,
    String text, {
    bool suppressFollowUpPaste = false,
  }) {
    snapshot.target.replaceSelection(text, snapshot.selection);
    if (suppressFollowUpPaste) {
      _suppressedPasteTarget = snapshot.target;
      _suppressPasteUntil = DateTime.now().add(
        const Duration(milliseconds: 300),
      );
    }
    _requestFocus(snapshot.target);
    _cancelRestore(expected: snapshot);
  }

  Future<void> _waitForCaptureRetry(Duration delay) {
    final completer = Completer<void>();
    _captureRetryTimer?.cancel();
    _captureRetryTimer = Timer(delay, () {
      _captureRetryTimer = null;
      completer.complete();
    });
    return completer.future;
  }

  bool _consumePasteSuppression() {
    final target = _suppressedPasteTarget;
    final deadline = _suppressPasteUntil;
    if (target == null || deadline == null) return false;
    if (DateTime.now().isAfter(deadline) || !target.focusNode.hasFocus) {
      _clearPasteSuppression();
      return false;
    }
    _clearPasteSuppression();
    return true;
  }

  void _clearPasteSuppression() {
    _suppressedPasteTarget = null;
    _suppressPasteUntil = null;
  }

  void _suppressMatchingPasteAction() {
    _skipNextPasteAction = true;
    scheduleMicrotask(() => _skipNextPasteAction = false);
  }

  bool _hasExternalEditableFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || _ownsFocus(focus)) return false;
    return focus.context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _ownsFocus(FocusNode focus) {
    return _targets.any((target) => target.focusNode == focus);
  }

  void _cancelRestore({_DesktopFocusSnapshot? expected}) {
    final snapshot = _snapshot;
    if (expected != null && !identical(snapshot, expected)) return;
    _snapshot = null;
    _pasteFallbackArmed = false;
    _autoPasteSessionId = null;
    _captureRetryTimer?.cancel();
    _captureRetryTimer = null;
    _resumedCaptureTimer?.cancel();
    _resumedCaptureTimer = null;
    if (snapshot != null) {
      unawaited(_clipboardReader.discardPendingPasteText(snapshot.sessionId));
    }
  }

  @override
  void onWindowBlur() => _suspendFocus();

  @override
  void onWindowFocus() => _restoreFocus();

  void dispose() {
    _disposed = true;
    _cancelRestore();
    _capturedPasteSubscription.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    windowManager.removeListener(this);
    for (final target in _targets) {
      target.focusNode.removeListener(_trackFocus);
      target.contentListenable.removeListener(_trackContentChange);
    }
    _lifecycle.dispose();
  }
}

class _DesktopFocusSnapshot {
  const _DesktopFocusSnapshot({
    required this.target,
    required this.content,
    required this.selection,
    required this.suspendedAt,
    required this.sessionId,
  });

  final DesktopClipboardTarget target;
  final String content;
  final Object selection;
  final DateTime suspendedAt;
  final int sessionId;
}
