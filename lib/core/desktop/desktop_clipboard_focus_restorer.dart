import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_clipboard_diagnostics.dart';
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

class DesktopClipboardPasteRegion extends StatelessWidget {
  const DesktopClipboardPasteRegion({
    super.key,
    required this.onPaste,
    required this.child,
  });

  final VoidCallback onPaste;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (_) {
            onPaste();
            return null;
          },
        ),
      },
      child: child,
    );
  }
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
    _pasteRequestSubscription = _clipboardReader.pasteRequests.listen(
      _handleNativePasteRequest,
    );
    unawaited(_clipboardReader.registerPasteTarget());
  }

  static const _clipboardSessionLimit = Duration(seconds: 30);
  static const _resumedCaptureLimit = Duration(seconds: 3);
  static const _pasteCaptureObservationRetryDelays = <Duration>[
    Duration(milliseconds: 4),
    Duration(milliseconds: 8),
    Duration(milliseconds: 16),
    Duration(milliseconds: 32),
    Duration(milliseconds: 64),
    Duration(milliseconds: 128),
    Duration(milliseconds: 256),
  ];
  static const _pasteCaptureTextRetryDelays = <Duration>[
    Duration(milliseconds: 4),
    Duration(milliseconds: 8),
    Duration(milliseconds: 16),
    Duration(milliseconds: 32),
    Duration(milliseconds: 64),
    Duration(milliseconds: 128),
    Duration(milliseconds: 256),
    Duration(milliseconds: 512),
    Duration(milliseconds: 1024),
    Duration(milliseconds: 1536),
  ];
  static int _nextSessionId = 0;

  final List<DesktopClipboardTarget> _targets;
  final _clipboardReader = const DesktopClipboardReader();
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<DesktopPasteRequest> _pasteRequestSubscription;
  DesktopClipboardTarget? _lastTarget;
  _DesktopFocusSnapshot? _snapshot;
  bool _pasteFallbackArmed = false;
  bool _disposed = false;
  bool _active = true;
  Timer? _captureRetryTimer;
  Completer<void>? _captureRetryCompleter;
  Timer? _resumedCaptureTimer;
  bool _pasteOperationInFlight = false;
  DesktopClipboardTarget? _suppressedPasteTarget;
  DateTime? _suppressPasteUntil;
  DateTime? _skipPasteActionUntil;

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

  void _suspendFocus() => _captureFocusSnapshot();

  void _captureFocusSnapshot({bool armNative = true}) {
    if (!_active) {
      DesktopClipboardDiagnostics.write('snapshot_skip', {
        'reason': 'inactive',
      });
      return;
    }
    if (_snapshot != null) {
      DesktopClipboardDiagnostics.write('snapshot_skip', {
        'reason': 'already_active',
        'session': _snapshot!.sessionId,
      });
      return;
    }
    if (_hasExternalEditableFocus()) {
      DesktopClipboardDiagnostics.write('snapshot_skip', {
        'reason': 'external_focus',
      });
      return;
    }
    final target = _focusedTarget() ?? _lastTarget;
    if (target == null || !target.isAvailable) {
      DesktopClipboardDiagnostics.write('snapshot_skip', {
        'reason': 'no_target',
      });
      return;
    }
    final sessionId = ++_nextSessionId;
    _clearPasteSuppression();
    final snapshot = _DesktopFocusSnapshot(
      target: target,
      content: target.text,
      selection: target.selection,
      suspendedAt: DateTime.now(),
      sessionId: sessionId,
      nativeCaptureReady: armNative
          ? _clipboardReader.armPasteCapture(sessionId)
          : Future<bool>.value(false),
    );
    _snapshot = snapshot;
    _pasteFallbackArmed = true;
    _resumedCaptureTimer?.cancel();
    DesktopClipboardDiagnostics.write('snapshot_captured', {
      'session': sessionId,
      'target': _targetIndex(target),
      'selection': snapshot.selection,
      'text_length': snapshot.content.length,
      'arm_native': armNative,
    });
  }

  void _restoreFocus() {
    if (!_active) {
      _cancelRestore();
      return;
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      _pasteFallbackArmed = false;
      DesktopClipboardDiagnostics.write('restore_skip', {
        'reason': 'no_snapshot',
      });
      return;
    }
    _restoreSelection(snapshot);
    _requestFocus(snapshot.target);
    _resumedCaptureTimer?.cancel();
    _resumedCaptureTimer = Timer(
      _resumedCaptureLimit,
      () => _cancelRestore(expected: snapshot),
    );
    DesktopClipboardDiagnostics.write('focus_restored', {
      'session': snapshot.sessionId,
      'target': _targetIndex(snapshot.target),
    });
  }

  void _restoreSelection(_DesktopFocusSnapshot snapshot) {
    if (_contentMatches(snapshot) && snapshot.target.isAvailable) {
      snapshot.target.restoreSelection(snapshot.selection);
    }
  }

  void _handleNativePasteRequest(DesktopPasteRequest request) {
    DesktopClipboardDiagnostics.write('request_handling', {
      'session': request.sessionId,
      'has_text': request.text != null,
      'length': request.text?.length,
      'active_session': _snapshot?.sessionId,
    });
    if (_snapshot == null && request.text != null) {
      _captureFocusSnapshot(armNative: false);
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      DesktopClipboardDiagnostics.write('request_drop', {
        'reason': 'no_snapshot',
      });
      return;
    }
    final sessionId = request.sessionId;
    if (sessionId != null && snapshot.sessionId != sessionId) {
      DesktopClipboardDiagnostics.write('request_drop', {
        'reason': 'session_mismatch',
        'session': sessionId,
        'active_session': snapshot.sessionId,
      });
      return;
    }
    final text = request.text;
    if (text != null) {
      if (text.isEmpty || !_canPaste(snapshot)) {
        DesktopClipboardDiagnostics.write('request_drop', {
          'reason': text.isEmpty ? 'empty_text' : 'snapshot_invalid',
          'session': snapshot.sessionId,
        });
        return;
      }
      _pasteFallbackArmed = false;
      _restoreSelection(snapshot);
      _requestFocus(snapshot.target);
      _pasteText(snapshot, text, suppressFollowUpPaste: true);
      return;
    }
    _pasteFallbackArmed = false;
    if (_pasteOperationInFlight) {
      // Windows can report that the paste key was pressed before the selected
      // clipboard text becomes readable. Wake the in-flight retry immediately
      // instead of dropping the native notification behind the operation lock.
      _cancelCaptureRetry();
      return;
    }
    _startExplicitPaste(snapshot, suppressFollowUpPaste: true);
  }

  bool _canPaste(_DesktopFocusSnapshot snapshot) {
    if (_disposed || !_active || !identical(_snapshot, snapshot)) {
      DesktopClipboardDiagnostics.write('paste_rejected', {
        'reason': 'snapshot_state',
        'session': snapshot.sessionId,
      });
      return false;
    }
    if (DateTime.now().difference(snapshot.suspendedAt) >
        _clipboardSessionLimit) {
      DesktopClipboardDiagnostics.write('paste_rejected', {
        'reason': 'session_expired',
        'session': snapshot.sessionId,
      });
      _cancelRestore(expected: snapshot);
      return false;
    }
    if (!snapshot.target.isAvailable || !_contentMatches(snapshot)) {
      DesktopClipboardDiagnostics.write('paste_rejected', {
        'reason': 'target_changed',
        'session': snapshot.sessionId,
        'target_available': snapshot.target.isAvailable,
        'content_matches': _contentMatches(snapshot),
      });
      _cancelRestore(expected: snapshot);
      return false;
    }
    if (_hasExternalEditableFocus()) {
      DesktopClipboardDiagnostics.write('paste_rejected', {
        'reason': 'external_focus',
        'session': snapshot.sessionId,
      });
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
    DesktopClipboardDiagnostics.write('paste_key', {
      'session': _snapshot?.sessionId,
      'fallback_armed': _pasteFallbackArmed,
      'external_focus': _hasExternalEditableFocus(),
    });
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
    _startExplicitPaste(snapshot, suppressFollowUpPaste: true);
    return true;
  }

  void pasteFocusedTarget() {
    DesktopClipboardDiagnostics.write('paste_action', {
      'session': _snapshot?.sessionId,
      'fallback_armed': _pasteFallbackArmed,
      'focused_target': _focusedTarget() == null
          ? null
          : _targetIndex(_focusedTarget()!),
    });
    if (_consumeMatchingPasteAction()) return;
    if (_consumePasteSuppression()) return;
    final snapshot = _snapshot;
    if (_pasteFallbackArmed && snapshot != null && _canPaste(snapshot)) {
      _pasteFallbackArmed = false;
      _startExplicitPaste(snapshot);
      return;
    }
    final target = _focusedTarget();
    if (target != null) unawaited(_pasteCurrentSelection(target));
  }

  void _startExplicitPaste(
    _DesktopFocusSnapshot snapshot, {
    bool suppressFollowUpPaste = false,
  }) {
    // A native paste notification and Flutter's own key event can arrive in
    // either order. Serialize the read/insert operation so the second path
    // cannot fall back to the restored clipboard and insert a duplicate value.
    if (_pasteOperationInFlight) {
      DesktopClipboardDiagnostics.write('paste_start_skip', {
        'reason': 'already_in_flight',
        'session': snapshot.sessionId,
      });
      return;
    }
    _pasteOperationInFlight = true;
    DesktopClipboardDiagnostics.write('paste_start', {
      'session': snapshot.sessionId,
      'suppress_follow_up': suppressFollowUpPaste,
    });
    unawaited(
      _pasteExplicitClipboard(
        snapshot,
        suppressFollowUpPaste: suppressFollowUpPaste,
      ).whenComplete(() => _pasteOperationInFlight = false),
    );
  }

  Future<void> _pasteExplicitClipboard(
    _DesktopFocusSnapshot snapshot, {
    bool suppressFollowUpPaste = false,
  }) async {
    final nativeCaptureReady = await snapshot.nativeCaptureReady;
    DesktopClipboardDiagnostics.write('paste_capture_ready', {
      'session': snapshot.sessionId,
      'native_ready': nativeCaptureReady,
    });
    if (!_canPaste(snapshot)) return;
    var text = nativeCaptureReady
        ? await _clipboardReader.readCapturedPasteText(snapshot.sessionId)
        : null;
    var observedChange = text != null;
    if (text == null) {
      observedChange = await _clipboardReader.didPasteCaptureObserveChange(
        snapshot.sessionId,
      );

      // The injected paste key can reach Flutter before Windows posts the first
      // WM_CLIPBOARDUPDATE for a clipboard manager. Give the native capture a
      // short observation window before falling back to the system clipboard;
      // otherwise the fallback can read the value that QuickClipboard has just
      // restored and insert the wrong item.
      if (!observedChange &&
          nativeCaptureReady &&
          defaultTargetPlatform == TargetPlatform.windows) {
        for (final delay in _pasteCaptureObservationRetryDelays) {
          await _waitForCaptureRetry(delay);
          if (!_canPaste(snapshot)) return;
          text = await _clipboardReader.readCapturedPasteText(
            snapshot.sessionId,
          );
          if (text != null) {
            observedChange = true;
            break;
          }
          observedChange = await _clipboardReader.didPasteCaptureObserveChange(
            snapshot.sessionId,
          );
          if (observedChange) break;
        }
      }
    }

    if (text == null && observedChange) {
      for (final delay in _pasteCaptureTextRetryDelays) {
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
    DesktopClipboardDiagnostics.write('paste_text_selected', {
      'session': snapshot.sessionId,
      'source': observedChange ? 'native_capture' : 'system_clipboard',
      'available': text != null,
      'length': text?.length,
    });
    if (!_canPaste(snapshot) || text == null || text.isEmpty) return;
    _pasteText(snapshot, text, suppressFollowUpPaste: suppressFollowUpPaste);
  }

  Future<void> _pasteCurrentSelection(DesktopClipboardTarget target) async {
    DesktopClipboardDiagnostics.write('paste_current_start', {
      'target': _targetIndex(target),
      'focused': target.focusNode.hasFocus,
    });
    final selection = target.selection;
    final text = await _clipboardReader.readSystemText();
    if (_disposed || text == null || text.isEmpty) {
      DesktopClipboardDiagnostics.write('paste_current_rejected', {
        'reason': _disposed ? 'disposed' : 'empty_text',
        'target': _targetIndex(target),
      });
      return;
    }
    if (!target.isAvailable) {
      DesktopClipboardDiagnostics.write('paste_current_rejected', {
        'reason': 'target_unavailable',
        'target': _targetIndex(target),
      });
      return;
    }
    if (!target.focusNode.hasFocus) _requestFocus(target);
    if (!target.focusNode.hasFocus) {
      DesktopClipboardDiagnostics.write('paste_current_rejected', {
        'reason': 'focus_not_restored',
        'target': _targetIndex(target),
      });
      return;
    }
    target.replaceSelection(text, selection);
    DesktopClipboardDiagnostics.write('paste_current_insert', {
      'target': _targetIndex(target),
      'length': text.length,
    });
    _requestFocus(target);
  }

  void _pasteText(
    _DesktopFocusSnapshot snapshot,
    String text, {
    bool suppressFollowUpPaste = false,
  }) {
    DesktopClipboardDiagnostics.write('paste_insert', {
      'session': snapshot.sessionId,
      'target': _targetIndex(snapshot.target),
      'length': text.length,
      'suppress_follow_up': suppressFollowUpPaste,
    });
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
    _cancelCaptureRetry();
    final completer = Completer<void>();
    _captureRetryCompleter = completer;
    _captureRetryTimer = Timer(delay, () {
      if (identical(_captureRetryCompleter, completer)) {
        _captureRetryTimer = null;
        _captureRetryCompleter = null;
      }
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void _cancelCaptureRetry() {
    _captureRetryTimer?.cancel();
    _captureRetryTimer = null;
    final completer = _captureRetryCompleter;
    _captureRetryCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
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
    _skipPasteActionUntil = DateTime.now().add(
      const Duration(milliseconds: 300),
    );
  }

  bool _consumeMatchingPasteAction() {
    final deadline = _skipPasteActionUntil;
    _skipPasteActionUntil = null;
    return deadline != null && !DateTime.now().isAfter(deadline);
  }

  bool _hasExternalEditableFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || _ownsFocus(focus)) return false;
    return focus.context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _ownsFocus(FocusNode focus) {
    return _targets.any((target) => target.focusNode == focus);
  }

  int? _targetIndex(DesktopClipboardTarget target) {
    final index = _targets.indexOf(target);
    return index < 0 ? null : index;
  }

  void _cancelRestore({_DesktopFocusSnapshot? expected}) {
    final snapshot = _snapshot;
    if (expected != null && !identical(snapshot, expected)) return;
    if (snapshot != null) {
      DesktopClipboardDiagnostics.write('snapshot_cancelled', {
        'session': snapshot.sessionId,
        'expected_match': expected == null || identical(snapshot, expected),
      });
    }
    _snapshot = null;
    _pasteFallbackArmed = false;
    _cancelCaptureRetry();
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
    _pasteRequestSubscription.cancel();
    unawaited(_clipboardReader.unregisterPasteTarget());
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
    required this.nativeCaptureReady,
  });

  final DesktopClipboardTarget target;
  final String content;
  final Object selection;
  final DateTime suspendedAt;
  final int sessionId;
  final Future<bool> nativeCaptureReady;
}
