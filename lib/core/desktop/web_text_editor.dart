import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_clipboard_diagnostics.dart';
import 'desktop_text_selection.dart';

/// A single browser-backed editing surface shared by macOS and Windows.
///
/// The DOM is authoritative for input, selection, undo, IME and clipboard
/// commands. Flutter keeps a document snapshot for business actions, while
/// the native responder only routes focus back to this editing surface.
class DesktopWebTextEditor extends StatefulWidget {
  const DesktopWebTextEditor({
    super.key,
    required this.text,
    this.selection,
    required this.onChanged,
    this.onSelectionChanged,
    this.onFind,
    this.backgroundColor,
    this.textColor,
    this.isDark = false,
    this.syntax = WebEditorSyntax.plain,
    this.readOnly = false,
    this.singleLine = false,
    this.placeholder,
    this.fontSize = 14,
    this.padding = const EdgeInsets.all(12),
    this.autofocus = true,
    this.highlights = const [],
    this.debugLabel = 'web-editor',
  });

  final String text;
  final NativeTextSelection? selection;
  final ValueChanged<String> onChanged;
  final ValueChanged<NativeTextSelection>? onSelectionChanged;
  final VoidCallback? onFind;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isDark;
  final WebEditorSyntax syntax;
  final bool readOnly;
  final bool singleLine;
  final String? placeholder;
  final double fontSize;
  final EdgeInsets padding;
  final bool autofocus;
  final List<DesktopTextHighlight> highlights;
  final String debugLabel;

  static bool get hasActiveEditor => _DesktopWebTextEditorState.hasActiveEditor;

  static void restoreActiveEditorFocus() {
    _DesktopWebTextEditorState.restoreActiveEditorFocus();
  }

  static void suspendActiveEditorFocus() {
    _DesktopWebTextEditorState.suspendActiveEditorFocus();
  }

  static void collapseActiveJson() {
    _DesktopWebTextEditorState.collapseActiveJson();
  }

  static void expandActiveJson() {
    _DesktopWebTextEditorState.expandActiveJson();
  }

  @override
  State<DesktopWebTextEditor> createState() => _DesktopWebTextEditorState();
}

enum WebEditorSyntax { plain, json }

class DesktopTextHighlight {
  const DesktopTextHighlight({
    required this.start,
    required this.end,
    required this.backgroundColor,
    this.textColor,
  });

  final int start;
  final int end;
  final Color backgroundColor;
  final Color? textColor;
}

class _DesktopWebTextEditorState extends State<DesktopWebTextEditor>
    with WindowListener {
  static _DesktopWebTextEditorState? _activeEditor;
  static const _focusChannel = MethodChannel('dev_orbit/clipboard');

  InAppWebViewController? _controller;
  bool _loaded = false;
  bool _disposed = false;
  bool _isVisible = true;
  bool _restoreFocusOnWindowFocus = false;
  bool _editorSessionActive = false;
  NativeTextSelection? _lastWebSelection;
  late final AppLifecycleListener _lifecycle;

  /// Whether a WebView editor owns the editing session that should survive a
  /// temporary native clipboard window. The flag intentionally remains true
  /// after the WebView emits `blur`: that blur is exactly what happens while a
  /// clipboard picker is in the foreground.
  static bool get hasActiveEditor {
    final editor = _activeEditor;
    return editor != null &&
        !editor._disposed &&
        editor._isVisible &&
        editor._editorSessionActive &&
        editor._restoreFocusOnWindowFocus;
  }

  /// Called by the outer desktop focus shell before it restores its own
  /// keyboard-shortcut focus node. Let the editor win that race instead.
  static void restoreActiveEditorFocus() {
    final editor = _activeEditor;
    if (editor == null ||
        editor._disposed ||
        !editor._isVisible ||
        !editor._editorSessionActive) {
      return;
    }
    editor._restoreFocusOnWindowFocus = true;
    editor._restoreWebFocus();
  }

  /// A Flutter text field layered above a WebView has taken over editing.
  /// Keep the DOM selection intact, but stop native window restoration from
  /// returning keyboard focus to the browser behind that field.
  static void suspendActiveEditorFocus() {
    final editor = _activeEditor;
    if (editor == null || editor._disposed) return;
    editor._editorSessionActive = false;
    editor._restoreFocusOnWindowFocus = false;
  }

  /// Collapse every foldable JSON block in the active WebView editor.
  ///
  /// The JSON toolbar lives outside the WebView, so it cannot call the DOM
  /// directly. Keep this small bridge here rather than exposing the private
  /// state object to feature pages.
  static void collapseActiveJson() {
    _activeEditor?._evaluateJavascript('window.devOrbitCollapseAll();');
  }

  /// Expand every folded JSON block in the active WebView editor.
  static void expandActiveJson() {
    _activeEditor?._evaluateJavascript('window.devOrbitExpandAll();');
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _lifecycle = AppLifecycleListener(
      onInactive: _onAppInactive,
      onResume: _onAppResume,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context);
    if (visible == _isVisible) return;
    _isVisible = visible;
    if (!visible) {
      // An IndexedStack keeps inactive tool pages mounted. They must not stay
      // eligible for focus restoration while another page is visible.
      if (identical(_activeEditor, this)) _activeEditor = null;
      _restoreFocusOnWindowFocus = false;
      _editorSessionActive = false;
      _evaluateJavascript('window.devOrbitBlur();');
      return;
    }
    if (widget.autofocus && _loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && _isVisible && widget.autofocus) {
          _focusEditorFromAutofocus();
        }
      });
    }
  }

  void _focusEditorFromAutofocus() {
    _claimEditorSession();
    _evaluateJavascript('window.devOrbitFocus();');
  }

  void _claimEditorSession() {
    final previous = _activeEditor;
    if (previous != null && !identical(previous, this)) {
      previous._restoreFocusOnWindowFocus = false;
      previous._editorSessionActive = false;
    }
    _activeEditor = this;
    _editorSessionActive = true;
    _restoreFocusOnWindowFocus = false;
  }

  void _onAppInactive() {
    if (_isVisible && identical(_activeEditor, this) && _editorSessionActive) {
      _restoreFocusOnWindowFocus = true;
    }
  }

  void _onAppResume() {
    if (!identical(_activeEditor, this) || !_restoreFocusOnWindowFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _restoreFocusOnWindowFocus) _restoreWebFocus();
    });
  }

  bool get _supported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows) &&
      Platform.environment['FLUTTER_TEST'] != 'true';

  @override
  void didUpdateWidget(covariant DesktopWebTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_loaded || _controller == null) return;
    if (oldWidget.text != widget.text ||
        oldWidget.selection != widget.selection ||
        oldWidget.readOnly != widget.readOnly ||
        oldWidget.singleLine != widget.singleLine ||
        oldWidget.placeholder != widget.placeholder ||
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.padding != widget.padding ||
        oldWidget.autofocus != widget.autofocus ||
        oldWidget.highlights != widget.highlights ||
        oldWidget.debugLabel != widget.debugLabel ||
        oldWidget.isDark != widget.isDark ||
        oldWidget.backgroundColor != widget.backgroundColor ||
        oldWidget.textColor != widget.textColor ||
        oldWidget.syntax != widget.syntax) {
      _syncState();
    }
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    _controller = controller;
    controller.addJavaScriptHandler(
      handlerName: 'editorChanged',
      callback: (args) {
        if (!_isVisible || _disposed) return null;
        if (args.length < 3 || args[0] is! String) return null;
        final selection = NativeTextSelection(
          baseOffset: _asInt(args[1]),
          extentOffset: _asInt(args[2]),
        );
        _lastWebSelection = selection;
        _traceSelection('web_input_selection', selection);
        // Consumers such as the JSON formatter clamp selections against
        // their current text length. Sending the selection before the new
        // text can turn a valid caret into 0,0.
        widget.onChanged(args[0] as String);
        widget.onSelectionChanged?.call(selection);
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'selectionChanged',
      callback: (args) {
        if (!_isVisible || _disposed) return null;
        if (args.length < 2) return null;
        final selection = NativeTextSelection(
          baseOffset: _asInt(args[0]),
          extentOffset: _asInt(args[1]),
        );
        _lastWebSelection = selection;
        _traceSelection('web_selection', selection);
        widget.onSelectionChanged?.call(selection);
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'findRequested',
      callback: (_) {
        widget.onFind?.call();
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'copyRequested',
      callback: (args) async {
        if (args.isEmpty || args.first is! String) return null;
        try {
          await Clipboard.setData(ClipboardData(text: args.first as String));
        } on PlatformException {
          // WebKit's native copy path remains available as a fallback.
        }
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'editorFocusChanged',
      callback: (args) {
        if (!_isVisible || _disposed) return null;
        if (args.isNotEmpty && args.first == true) {
          _claimEditorSession();
          if (args.length >= 3) {
            final selection = NativeTextSelection(
              baseOffset: _asInt(args[1]),
              extentOffset: _asInt(args[2]),
            );
            _lastWebSelection = selection;
            _traceSelection('web_focus', selection);
            widget.onSelectionChanged?.call(selection);
          }
        } else {
          if (args.length >= 3) {
            final selection = NativeTextSelection(
              baseOffset: _asInt(args[1]),
              extentOffset: _asInt(args[2]),
            );
            _lastWebSelection = selection;
            _traceSelection('web_blur', selection);
            widget.onSelectionChanged?.call(selection);
          }
          // A Flutter find/replace TextField can sit above this WebView. Its
          // focus is a deliberate editor switch, unlike a native window blur
          // where no Flutter EditableText owns focus yet. Keep the session for
          // the latter so clipboard return can still restore the WebView.
          final flutterEditableFocused =
              FocusManager.instance.primaryFocus?.context
                  ?.findAncestorStateOfType<EditableTextState>() !=
              null;
          if (flutterEditableFocused) _editorSessionActive = false;
        }
        return null;
      },
    );
  }

  void _onPointerDown(PointerDownEvent _) {
    if (!_isVisible || _disposed) return;
    // DOM focus does not fire when an already-focused editor is clicked a
    // second time. Claim the editor directly from Flutter's pointer stream so
    // focus recovery does not depend on a delayed JavaScript bridge callback.
    _claimEditorSession();
    if (Platform.isWindows) unawaited(_claimNativeEditorFocus());
  }

  int _asInt(Object? value) => value is num ? value.toInt() : 0;

  void _traceSelection(String event, NativeTextSelection selection) {
    DesktopClipboardDiagnostics.write(event, {
      'editor': widget.debugLabel,
      'base': selection.baseOffset,
      'extent': selection.extentOffset,
      'text_length': widget.text.length,
    });
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    _loaded = true;
    _syncState();
    if (widget.autofocus && _isVisible) {
      Future<void>.delayed(const Duration(milliseconds: 60), () {
        if (!_disposed && _isVisible && widget.autofocus) {
          _focusEditorFromAutofocus();
        }
      });
    }
  }

  void _restoreWebFocus({int attempt = 0}) {
    final controller = _controller;
    if (_disposed ||
        !_loaded ||
        !_isVisible ||
        !identical(_activeEditor, this) ||
        !_editorSessionActive ||
        controller == null) {
      return;
    }
    if (attempt == 0 || attempt == 3) {
      unawaited(_requestNativeEditorFocus());
    }
    controller.evaluateJavascript(source: 'window.devOrbitRestoreFocus();');
    if (attempt >= 5) {
      _restoreFocusOnWindowFocus = false;
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 40 + attempt * 40), () {
      if (!_disposed &&
          _isVisible &&
          identical(_activeEditor, this) &&
          _editorSessionActive &&
          _restoreFocusOnWindowFocus) {
        _restoreWebFocus(attempt: attempt + 1);
      }
    });
  }

  @override
  void onWindowBlur() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final flutterEditableFocused =
        primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() !=
        null;
    _restoreFocusOnWindowFocus =
        _isVisible &&
        identical(_activeEditor, this) &&
        (_editorSessionActive || !flutterEditableFocused);
  }

  @override
  void onWindowFocus() {
    if (!_isVisible ||
        !identical(_activeEditor, this) ||
        (!_editorSessionActive && !_restoreFocusOnWindowFocus)) {
      return;
    }
    _restoreFocusOnWindowFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreWebFocus();
    });
  }

  Future<void> _requestNativeEditorFocus() async {
    if (!_supported) return;
    try {
      await _focusChannel.invokeMethod<void>('requestEditorFocus');
    } on MissingPluginException {
      // The method is only available in the desktop runners.
    } on PlatformException {
      // Native focus recovery is best effort; the DOM recovery still runs.
    }
  }

  Future<void> _claimNativeEditorFocus() async {
    if (!_supported || !Platform.isWindows) return;
    try {
      await _focusChannel.invokeMethod<void>('claimEditorFocus');
    } on MissingPluginException {
      // The method is only available in the Windows runner.
    } on PlatformException {
      // The DOM still owns the selection if native focus cannot be adjusted.
    }
  }

  void _evaluateJavascript(String source) {
    final controller = _controller;
    if (_disposed || !_loaded || controller == null) return;
    unawaited(controller.evaluateJavascript(source: source));
  }

  void _syncState() {
    final controller = _controller;
    if (_disposed || !_loaded || controller == null) return;
    final selection =
        widget.selection ??
        NativeTextSelection(
          baseOffset: widget.text.length,
          extentOffset: widget.text.length,
        );
    final payload = jsonEncode({
      'text': widget.text,
      'baseOffset': selection.baseOffset,
      'extentOffset': selection.extentOffset,
      // A selection just reported by the DOM is only a Flutter-side mirror.
      // Do not echo it back into the active editor. A differing value is an
      // explicit external command, such as a find-result jump.
      'applySelection': selection != _lastWebSelection,
      'readOnly': widget.readOnly,
      'findEnabled': widget.onFind != null,
      'syntax': widget.syntax.name,
      'singleLine': widget.singleLine,
      'placeholder': widget.placeholder,
      'fontSize': widget.fontSize,
      'padding': {
        'left': widget.padding.left,
        'top': widget.padding.top,
        'right': widget.padding.right,
        'bottom': widget.padding.bottom,
      },
      'autofocus': widget.autofocus,
      'highlights': [
        for (final highlight in widget.highlights)
          {
            'start': highlight.start,
            'end': highlight.end,
            'backgroundColor': _cssColor(highlight.backgroundColor),
            if (highlight.textColor != null)
              'textColor': _cssColor(highlight.textColor!),
          },
      ],
      'isDark': widget.isDark,
      'backgroundColor': _cssColor(
        widget.backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerLowest,
      ),
      'textColor': _cssColor(
        widget.textColor ?? Theme.of(context).colorScheme.onSurface,
      ),
    });
    controller.evaluateJavascript(source: 'window.devOrbitSetState($payload);');
  }

  String _cssColor(Color color) =>
      '#${(color.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0')}'
      '${(color.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0')}'
      '${(color.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0')}';

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    if (identical(_activeEditor, this)) _activeEditor = null;
    windowManager.removeListener(this);
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    return Listener(
      onPointerDown: _onPointerDown,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: _editorHtml,
          baseUrl: WebUri('https://dev-orbit.local/'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          disableContextMenu: false,
          transparentBackground: true,
          supportZoom: false,
          allowsBackForwardNavigationGestures: false,
        ),
        onWebViewCreated: _onWebViewCreated,
        onLoadStop: _onLoadStop,
        onWindowBlur: (_) => onWindowBlur(),
        onWindowFocus: (_) => onWindowFocus(),
        gestureRecognizers: const {},
      ),
    );
  }
}

const _editorHtml = r'''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; }
  body { background: #fbfcfc; color: #383a42; }
  .editor-shell {
    display: flex; width: 100%; height: 100%; overflow: hidden;
  }
  #line-numbers {
    display: none; flex: 0 0 50px; height: 100%; overflow: hidden;
    border-right: 1px solid rgba(127, 127, 127, .16);
    background: rgba(127, 127, 127, .045); color: rgba(80, 88, 100, .72);
    font: 14px/1.55 Menlo, Consolas, monospace; text-align: right;
    user-select: none; pointer-events: none;
  }
  .editor-shell.json #line-numbers { display: block; }
  .editor-shell.dark #line-numbers {
    border-right-color: rgba(255, 255, 255, .12);
    background: rgba(255, 255, 255, .035); color: rgba(220, 228, 235, .58);
  }
  #line-numbers-content { min-height: 100%; }
  .line-number { height: 1.55em; line-height: 1.55; padding-right: 10px; }
  #editor {
    flex: 1; min-width: 0; width: auto; height: 100%; padding: 12px;
    overflow: auto; outline: none; white-space: pre-wrap;
    overflow-wrap: anywhere;
    tab-size: 2; font: 14px/1.55 Menlo, Consolas, monospace;
    caret-color: currentColor; user-select: text;
  }
  .editor-shell.json #editor { white-space: pre; overflow-wrap: normal; }
  #editor.single-line { white-space: pre; overflow-x: auto; overflow-y: hidden; }
  #editor:empty::before { color: rgba(127, 127, 127, .72); content: attr(data-placeholder); pointer-events: none; }
  .json-key { color: #986801; }
  .json-string { color: #318f4f; }
  .json-number { color: #986801; }
  .json-literal { color: #007fb9; }
  .json-null { color: #a626a4; }
  /* Keep the fold control outside the text width while giving it a clear,
     forgiving hit target before the opening brace. */
  .fold-toggle {
    display: inline-flex;
    width: 18px; height: 18px; margin-left: -18px; margin-right: 0;
    vertical-align: middle; align-items: center; justify-content: center;
    border: 1px solid rgba(100, 110, 125, .34); border-radius: 5px;
    background: rgba(100, 110, 125, .08); color: currentColor;
    cursor: pointer;
    user-select: none;
    transition: background .12s ease, border-color .12s ease, transform .12s ease;
  }
  .fold-toggle::before {
    content: ''; display: block; width: 6px; height: 6px;
    border-right: 1.8px solid currentColor; border-bottom: 1.8px solid currentColor;
    transform: rotate(45deg) translate(-1px, -1px); opacity: .82;
  }
  .fold-toggle.collapsed::before { transform: rotate(-45deg) translate(-1px, -1px); }
  .fold-toggle:hover {
    background: rgba(80, 120, 180, .16); border-color: currentColor;
    transform: translateY(-.5px) scale(1.05);
  }
  .fold-toggle:active { transform: scale(.96); }
  .fold-placeholder {
    display: inline-flex; align-items: center; min-height: 1.35em;
    margin: 0 3px; padding: 0 5px;
    border-radius: 4px;
    background: rgba(100, 110, 125, .10);
    color: rgba(80, 88, 100, .72);
    font: 500 .82em/1.35 -apple-system, BlinkMacSystemFont, sans-serif;
    vertical-align: .08em; cursor: pointer; user-select: none;
    transition: background .12s ease, color .12s ease;
  }
  .fold-placeholder::before { content: attr(data-fold-label); }
  .fold-placeholder:hover {
    background: rgba(80, 120, 180, .16); color: currentColor;
  }
  .editor-shell.dark .fold-placeholder {
    background: rgba(255, 255, 255, .09);
    color: rgba(220, 228, 235, .62);
  }
  .fold-hidden { display: none; }
</style>
</head>
<body><div class="editor-shell" id="editor-shell">
  <div id="line-numbers" aria-hidden="true"><div id="line-numbers-content"></div></div>
  <div id="editor" contenteditable="true" spellcheck="false"></div>
</div>
<script>
const editor = document.getElementById('editor');
const editorShell = document.getElementById('editor-shell');
const lineNumbers = document.getElementById('line-numbers');
const lineNumbersContent = document.getElementById('line-numbers-content');
let state = { text: '', baseOffset: 0, extentOffset: 0, syntax: 'plain', readOnly: false, findEnabled: false, highlights: [] };
let composing = false;
let inputPending = false;
let inputCommitScheduled = false;
let restoreAfterWindowFocus = false;
let collapsedFolds = [];
const bridge = (name, args) => {
  if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler(name, ...args);
};
const escapeHtml = value => String(value).replace(/[&<>"']/g, ch => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
}[ch]));
function textLength(node) {
  if (node.nodeType === Node.TEXT_NODE) return node.nodeValue.length;
  let total = 0;
  node.childNodes.forEach(child => total += textLength(child));
  return total;
}
function selectionOffset(root, target, localOffset) {
  let total = 0, found = false;
  const walk = node => {
    if (found) return;
    if (node === target) {
      if (node.nodeType === Node.TEXT_NODE) {
        total += Math.min(localOffset, node.nodeValue.length);
      } else {
        for (let index = 0; index < Math.min(localOffset, node.childNodes.length); index++) {
          total += textLength(node.childNodes[index]);
        }
      }
      found = true; return;
    }
    if (node.nodeType === Node.TEXT_NODE) { total += node.nodeValue.length; return; }
    node.childNodes.forEach(walk);
  };
  walk(root);
  return total;
}
function locate(root, offset) {
  let remaining = Math.max(0, offset), result = { node: root, offset: 0 };
  const walk = node => {
    if (node.nodeType === Node.TEXT_NODE) {
      if (remaining <= node.nodeValue.length) {
        result = { node, offset: remaining }; return true;
      }
      remaining -= node.nodeValue.length; return false;
    }
    for (const child of node.childNodes) if (walk(child)) return true;
    return false;
  };
  walk(root); return result;
}
function currentSelection() {
  const selection = window.getSelection();
  if (!selection || !selection.rangeCount) return [0, 0];
  const range = selection.getRangeAt(0);
  return [
    selectionOffset(editor, range.startContainer, range.startOffset),
    selectionOffset(editor, range.endContainer, range.endOffset)
  ];
}
function insertPlainText(value) {
  const selection = window.getSelection();
  if (!selection || !selection.rangeCount) return;
  const range = selection.getRangeAt(0);
  range.deleteContents();
  const node = document.createTextNode(value);
  range.insertNode(node);
  range.setStartAfter(node);
  range.collapse(true);
  selection.removeAllRanges();
  selection.addRange(range);
  editor.dispatchEvent(new InputEvent('input', {
    bubbles: true,
    inputType: 'insertText',
    data: value
  }));
}
function restoreSelection(base, extent) {
  const selection = window.getSelection();
  if (!selection) return;
  const start = locate(editor, Math.min(base, extent));
  const end = locate(editor, Math.max(base, extent));
  const range = document.createRange();
  range.setStart(start.node, start.offset); range.setEnd(end.node, end.offset);
  selection.removeAllRanges(); selection.addRange(range);
  lastSelection = [base, extent];
}
// textContent includes the contents of display:none fold spans, while the
// empty fold-toggle elements contribute no characters. This keeps offsets
// stable while a JSON block is collapsed. When everything is expanded, keep
// innerText's normal handling of browser-created block elements (for example
// from a rich clipboard paste).
function readText() {
  const value = state.syntax === 'json' && collapsedFolds.length
    ? readTreeText(editor)
    : editor.innerText;
  return value.replace(/\r/g, '');
}
function readTreeText(node) {
  if (node.nodeType === Node.TEXT_NODE) return node.nodeValue;
  if (node.nodeType !== Node.ELEMENT_NODE) return '';
  if (node.tagName === 'BR') return '\n';
  let value = '';
  const children = Array.from(node.childNodes);
  children.forEach((child, index) => {
    value += readTreeText(child);
    const block = child.nodeType === Node.ELEMENT_NODE &&
      (child.tagName === 'DIV' || child.tagName === 'P');
    if (block && index < children.length - 1 && !value.endsWith('\n')) value += '\n';
  });
  return value;
}
function jsonFoldRanges(text) {
  const pairs = { '{': '}', '[': ']' };
  const closing = { '}': true, ']': true };
  const stack = [];
  const ranges = [];
  let inString = false;
  let escaped = false;
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    if (inString) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === '"') inString = false;
      continue;
    }
    if (character === '"') { inString = true; continue; }
    if (pairs[character]) {
      stack.push({ character, index });
      continue;
    }
    if (!closing[character] || !stack.length) continue;
    for (let stackIndex = stack.length - 1; stackIndex >= 0; stackIndex--) {
      const opening = stack[stackIndex];
      if (pairs[opening.character] !== character) continue;
      stack.splice(stackIndex, 1);
      if (index > opening.index + 1 && text.slice(opening.index + 1, index).includes('\n')) {
        ranges.push({ start: opening.index, end: index, close: character });
      }
      break;
    }
  }
  return ranges.sort((a, b) => a.start - b.start);
}
function foldRangeAt(text, offset) {
  const ranges = jsonFoldRanges(text);
  return ranges.find(range => range.start === offset) || null;
}
function foldMarker(start) {
  const collapsed = collapsedFolds.includes(start) ? ' collapsed' : '';
  return `<span class="fold-toggle${collapsed}" data-fold-start="${start}" contenteditable="false" aria-label="折叠或展开"></span>`;
}
function updateLineNumbers(text) {
  if (state.syntax !== 'json') {
    lineNumbersContent.innerHTML = '';
    return;
  }
  const ranges = jsonFoldRanges(text);
  const lineStarts = [0];
  for (let index = 0; index < text.length; index++) {
    if (text[index] === '\n') lineStarts.push(index + 1);
  }
  lineNumbersContent.innerHTML = lineStarts.map((start, index) => {
    const hidden = ranges.some(range =>
      collapsedFolds.includes(range.start) &&
      start > range.start && start <= range.end
    );
    return hidden ? '' : `<div class="line-number">${index + 1}</div>`;
  }).join('');
  lineNumbers.scrollTop = editor.scrollTop;
}
function escapeWithFoldMarkers(value, start, ranges) {
  let html = '';
  for (let index = 0; index < value.length; index++) {
    const absolute = start + index;
    const range = ranges.find(candidate => candidate.start === absolute);
    if (range) html += foldMarker(absolute);
    html += escapeHtml(value[index]);
  }
  return html;
}
function highlightedRanges(text) {
  const ranges = Array.isArray(state.highlights) ? state.highlights : [];
  if (!ranges.length) return escapeHtml(text);
  let html = '', cursor = 0;
  for (const range of ranges.slice().sort((a, b) => a.start - b.start)) {
    const start = Math.max(cursor, Math.min(text.length, Number(range.start) || 0));
    const end = Math.max(start, Math.min(text.length, Number(range.end) || 0));
    if (end <= start) continue;
    html += escapeHtml(text.slice(cursor, start));
    const background = escapeHtml(String(range.backgroundColor || 'transparent'));
    const color = range.textColor ? `color:${escapeHtml(String(range.textColor))};` : '';
    html += `<span style="background:${background};${color}">${escapeHtml(text.slice(start, end))}</span>`;
    cursor = end;
  }
  return html + escapeHtml(text.slice(cursor));
}
function highlighted(text) {
  if (state.syntax !== 'json') return highlightedRanges(text);
  const folds = jsonFoldRanges(text);
  const token = /("(?:\\.|[^"\\])*")|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)|\b(true|false|null)\b/g;
  let html = '', last = 0, match;
  while ((match = token.exec(text))) {
    html += escapeWithFoldMarkers(text.slice(last, match.index), last, folds);
    const value = match[0], after = text.slice(token.lastIndex);
    let cls = 'json-string';
    if (match[2]) cls = 'json-number';
    if (match[3] === 'null') cls = 'json-null';
    if (match[3] && match[3] !== 'null') cls = 'json-literal';
    if (match[1] && /^\s*:/.test(after)) cls = 'json-key';
    html += '<span class="' + cls + '">' + escapeWithFoldMarkers(value, match.index, folds) + '</span>';
    last = token.lastIndex;
  }
  return html + escapeWithFoldMarkers(text.slice(last), last, folds);
}
function applyCollapsedFolds(text) {
  if (state.syntax !== 'json' || !collapsedFolds.length) return;
  const ranges = jsonFoldRanges(text);
  // Apply outer ranges first. Nested ranges then remain inside their parent's
  // hidden span and become visible again when the parent is expanded.
  for (const range of ranges) {
    if (!collapsedFolds.includes(range.start)) continue;
    const start = locate(editor, range.start + 1);
    const end = locate(editor, range.end);
    const domRange = document.createRange();
    domRange.setStart(start.node, start.offset);
    domRange.setEnd(end.node, end.offset);
    const hidden = document.createElement('span');
    hidden.className = 'fold-hidden';
    hidden.dataset.foldEnd = String(range.end);
    hidden.appendChild(domRange.extractContents());
    domRange.insertNode(hidden);
    const hiddenText = text.slice(range.start + 1, range.end).trim();
    const lineCount = hiddenText ? hiddenText.split('\n').length : 0;
    const placeholder = document.createElement('span');
    placeholder.className = 'fold-placeholder';
    placeholder.contentEditable = 'false';
    placeholder.dataset.foldStart = String(range.start);
    placeholder.dataset.foldLabel = lineCount > 0 ? `... ${lineCount} 行` : '...';
    placeholder.setAttribute('aria-label', `已折叠 ${lineCount} 行，点击展开`);
    hidden.parentNode.insertBefore(placeholder, hidden);
  }
}

function textOffsetAtPoint(x, y) {
  const caretRange = document.caretRangeFromPoint
    ? document.caretRangeFromPoint(x, y)
    : null;
  if (!caretRange || !editor.contains(caretRange.startContainer)) return null;
  const caretOffset = selectionOffset(
    editor,
    caretRange.startContainer,
    caretRange.startOffset,
  );
  const text = readText();
  for (const offset of [caretOffset, caretOffset - 1]) {
    if (offset < 0 || offset >= text.length || !'{['.includes(text[offset])) continue;
    const start = locate(editor, offset);
    const end = locate(editor, offset + 1);
    const range = document.createRange();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
    for (const rect of range.getClientRects()) {
      if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
        return offset;
      }
    }
  }
  return null;
}
function rerenderPreservingSelection(text, base, extent) {
  editor.innerHTML = highlighted(text);
  applyCollapsedFolds(text);
  updateLineNumbers(text);
  const ranges = jsonFoldRanges(text);
  const visibleOffset = offset => {
    for (const range of ranges) {
      if (collapsedFolds.includes(range.start) &&
          offset > range.start && offset < range.end) {
        return range.start + 1;
      }
    }
    return offset;
  };
  restoreSelection(visibleOffset(base), visibleOffset(extent));
}
function render(text, base, extent, preserve) {
  const saved = preserve ? currentSelection() : [base, extent];
  rerenderPreservingSelection(
    text,
    preserve ? saved[0] : base,
    preserve ? saved[1] : extent,
  );
}
function toggleFoldAt(offset) {
  if (state.syntax !== 'json' || state.readOnly) return;
  const text = readText();
  const range = foldRangeAt(text, offset);
  if (!range) return;
  const selection = currentSelection();
  const index = collapsedFolds.indexOf(range.start);
  if (index >= 0) collapsedFolds.splice(index, 1);
  else collapsedFolds.push(range.start);
  rerenderPreservingSelection(text, selection[0], selection[1]);
}
window.devOrbitCollapseAll = () => {
  if (state.syntax !== 'json') return;
  collapsedFolds = jsonFoldRanges(readText()).map(range => range.start);
  const selection = currentSelection();
  rerenderPreservingSelection(readText(), selection[0], selection[1]);
};
window.devOrbitExpandAll = () => {
  if (state.syntax !== 'json') return;
  const text = readText();
  const selection = currentSelection();
  collapsedFolds = [];
  rerenderPreservingSelection(text, selection[0], selection[1]);
};
window.devOrbitSetState = next => {
  const changedText = next.text !== readText();
  const changedSyntax = state.syntax !== next.syntax;
  state = Object.assign(state, next);
  editorShell.classList.toggle('json', state.syntax === 'json');
  editorShell.classList.toggle('dark', !!state.isDark);
  if (changedText || changedSyntax) collapsedFolds = [];
  editor.style.background = next.backgroundColor || '#fbfcfc';
  editor.style.color = next.textColor || '#383a42';
  editor.classList.toggle('single-line', !!next.singleLine);
  editor.dataset.placeholder = next.placeholder || '';
  editor.style.fontSize = (next.fontSize || 14) + 'px';
  const padding = next.padding || {};
  const leftPadding = state.syntax === 'json'
    ? Math.max(20, Number(padding.left ?? 12))
    : Number(padding.left ?? 12);
  editor.style.padding = `${padding.top ?? 12}px ${padding.right ?? 12}px ${padding.bottom ?? 12}px ${leftPadding}px`;
  lineNumbers.style.fontSize = `${next.fontSize || 14}px`;
  lineNumbers.style.paddingTop = `${padding.top ?? 12}px`;
  lineNumbers.style.paddingBottom = `${padding.bottom ?? 12}px`;
  document.documentElement.style.colorScheme = next.isDark ? 'dark' : 'light';
  editor.contentEditable = next.readOnly ? 'false' : 'true';
  if (changedText || changedSyntax) {
    render(next.text, next.baseOffset, next.extentOffset, false);
  } else if (document.activeElement !== editor) {
    // Flutter rebuilds can arrive while a clipboard picker owns the native
    // focus. Do not move the DOM caret, or overwrite its saved range, with a
    // stale Flutter selection while the editor is temporarily inactive; the
    // window-focus callback restores the range captured before blur.
  } else if (next.applySelection) {
    // DOM selection is authoritative while the user is editing. Flutter only
    // writes a selection back when it represents an explicit external action.
    restoreSelection(next.baseOffset, next.extentOffset);
  }
};
let lastSelection = [0, 0];
let selectionFrozen = false;
window.devOrbitRestoreFocus = () => {
  selectionFrozen = true;
  restoreSelection(lastSelection[0], lastSelection[1]);
  editor.focus();
  restoreSelection(lastSelection[0], lastSelection[1]);
};
window.devOrbitFocus = () => {
  selectionFrozen = true;
  restoreSelection(lastSelection[0], lastSelection[1]);
  editor.focus();
  restoreSelection(lastSelection[0], lastSelection[1]);
};
window.devOrbitBlur = () => editor.blur();
window.addEventListener('blur', () => {
  if (document.activeElement === editor) {
    // WebKit can emit a zeroed selectionchange after the window has already
    // blurred. Freeze the last real caret until focus is restored.
    restoreAfterWindowFocus = true;
    selectionFrozen = true;
  }
});
window.addEventListener('focus', () => {
  if (!restoreAfterWindowFocus) return;
  restoreAfterWindowFocus = false;
  setTimeout(() => window.devOrbitRestoreFocus(), 0);
});
editor.addEventListener('focus', () => {
  // WebKit can report a transient [0, 0] range while focus is moving between
  // the native WKWebView and its contenteditable element. Keep the last range
  // observed while the editor was active; selectionchange will publish the
  // new mouse-click position immediately afterwards.
  const selection = lastSelection;
  bridge('editorFocusChanged', [true, selection[0], selection[1]]);
});
editor.addEventListener('blur', () => {
  // Do not read window.getSelection() after blur. On macOS it can already be
  // collapsed at offset zero even though the caret was at the end of the
  // document before a clipboard window took focus.
  selectionFrozen = true;
  bridge('editorFocusChanged', [false, lastSelection[0], lastSelection[1]]);
});
function scheduleInputCommit() {
  if (inputCommitScheduled) return;
  inputCommitScheduled = true;
  setTimeout(() => {
    inputCommitScheduled = false;
    if (composing || !inputPending) return;
    const text = readText(), selection = currentSelection();
    collapsedFolds = [];
    lastSelection = selection;
    render(text, selection[0], selection[1], false);
    // Text and selection cross the bridge as one committed edit. Flutter
    // never observes the temporary marked text used by an IME.
    bridge('editorChanged', [text, selection[0], selection[1]]);
    inputPending = false;
  }, 0);
}
editor.addEventListener('beforeinput', () => {
  // Selection changes caused by this edit must not reach Flutter before its
  // text does. This is essential for marked text from Chinese/Japanese IMEs.
  inputPending = true;
});
editor.addEventListener('compositionstart', () => {
  selectionFrozen = false;
  composing = true;
  inputPending = true;
});
editor.addEventListener('compositionend', () => {
  composing = false;
  inputPending = true;
  // WebKit versions disagree on whether the final input event is dispatched
  // before or after compositionend. A deferred, deduplicated commit supports
  // both orders without rebuilding the DOM while marked text is still live.
  scheduleInputCommit();
});
editor.addEventListener('input', () => {
  selectionFrozen = false;
  inputPending = true;
  if (!composing) scheduleInputCommit();
});
editor.addEventListener('click', event => {
  const marker = event.target.closest ? event.target.closest('.fold-toggle') : null;
  if (marker && editor.contains(marker)) {
    event.preventDefault();
    event.stopPropagation();
    toggleFoldAt(Number(marker.dataset.foldStart));
    return;
  }
  const placeholder = event.target.closest
    ? event.target.closest('.fold-placeholder')
    : null;
  if (placeholder && editor.contains(placeholder)) {
    event.preventDefault();
    event.stopPropagation();
    toggleFoldAt(Number(placeholder.dataset.foldStart));
    return;
  }
  if (state.syntax !== 'json' || state.readOnly) return;
  // Hit-test the actual glyph. A caret offset alone only identifies the gap
  // beside a character, which made clicks to the right of a brace fold it.
  const offset = textOffsetAtPoint(event.clientX, event.clientY);
  if (offset !== null) toggleFoldAt(offset);
});
editor.addEventListener('mousedown', () => selectionFrozen = false, true);
editor.addEventListener('scroll', () => { lineNumbers.scrollTop = editor.scrollTop; }, { passive: true });
document.addEventListener('selectionchange', () => {
  if (selectionFrozen || composing || inputPending || document.activeElement !== editor) return;
  const selection = currentSelection();
  if (selection[0] === lastSelection[0] && selection[1] === lastSelection[1]) return;
  lastSelection = selection;
  bridge('selectionChanged', selection);
});
editor.addEventListener('keydown', event => {
  selectionFrozen = false;
  // Let WebKit and the platform input method own every key while marked text
  // is active. keyCode 229 covers older WebKit versions where isComposing is
  // briefly false even though the IME still owns the event.
  if (event.isComposing || composing || event.keyCode === 229) return;
  const modified = event.metaKey || event.ctrlKey;
  const key = event.key.toLowerCase();
  if (modified && key === 'a') {
    // WebKit can route the command to the Flutter focus tree when the native
    // responder is settling. Keep select-all deterministic at the DOM layer.
    event.preventDefault();
    editor.focus();
    const length = readText().length;
    restoreSelection(0, length);
    lastSelection = [0, length];
    bridge('selectionChanged', [0, length]);
    return;
  }
  if (modified && key === 'c') {
    const selection = currentSelection();
    if (selection[0] !== selection[1]) {
      event.preventDefault();
      const start = Math.min(selection[0], selection[1]);
      const end = Math.max(selection[0], selection[1]);
      bridge('copyRequested', [readText().slice(start, end)]);
    }
    return;
  }
  if (state.findEnabled && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'f') {
    event.preventDefault(); bridge('findRequested', []); return;
  }
  if (event.key === 'Tab') {
    event.preventDefault(); document.execCommand('insertText', false, '  ');
  }
  if (event.key === 'Enter' && !composing) {
    event.preventDefault();
    if (!state.singleLine) insertPlainText('\n');
  }
});
</script></body></html>''';
