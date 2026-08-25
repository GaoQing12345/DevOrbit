import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_text_selection.dart';

/// A single browser-backed editing surface shared by macOS and Windows.
///
/// Keeping the input, selection, undo stack, IME and clipboard in one WebView
/// avoids platform-specific responder/focus bridges. The surrounding Flutter
/// page still owns document state and business actions.
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

  InAppWebViewController? _controller;
  bool _loaded = false;
  bool _disposed = false;
  bool _restoreFocusOnWindowFocus = false;
  final _webFocusNode = FocusNode(debugLabel: 'desktop web editor');

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
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
        if (args.length < 3 || args[0] is! String) return null;
        widget.onChanged(args[0] as String);
        widget.onSelectionChanged?.call(
          NativeTextSelection(
            baseOffset: _asInt(args[1]),
            extentOffset: _asInt(args[2]),
          ),
        );
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'selectionChanged',
      callback: (args) {
        if (args.length < 2) return null;
        widget.onSelectionChanged?.call(
          NativeTextSelection(
            baseOffset: _asInt(args[0]),
            extentOffset: _asInt(args[1]),
          ),
        );
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
      handlerName: 'editorFocusChanged',
      callback: (args) {
        if (args.isNotEmpty && args.first == true) {
          _activeEditor = this;
        }
        return null;
      },
    );
  }

  int _asInt(Object? value) => value is num ? value.toInt() : 0;

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    _loaded = true;
    _syncState();
    if (widget.autofocus) {
      _webFocusNode.requestFocus();
      Future<void>.delayed(const Duration(milliseconds: 60), () {
        if (!_disposed) {
          controller.evaluateJavascript(source: 'window.devOrbitFocus();');
        }
      });
    }
  }

  void _restoreWebFocus({int attempt = 0}) {
    final controller = _controller;
    if (_disposed || !_loaded || controller == null) return;
    if (!_webFocusNode.hasFocus) _webFocusNode.requestFocus();
    controller.evaluateJavascript(source: 'window.devOrbitRestoreFocus();');
    if (attempt >= 5) {
      _restoreFocusOnWindowFocus = false;
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 40 + attempt * 40), () {
      if (!_disposed && _restoreFocusOnWindowFocus) {
        _restoreWebFocus(attempt: attempt + 1);
      }
    });
  }

  @override
  void onWindowBlur() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    final flutterEditableFocused = primaryFocus
        ?.context
        ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    _restoreFocusOnWindowFocus =
        identical(_activeEditor, this) && !flutterEditableFocused;
  }

  @override
  void onWindowFocus() {
    if (!_restoreFocusOnWindowFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreWebFocus();
    });
  }

  void _syncState() {
    final controller = _controller;
    if (_disposed || !_loaded || controller == null) return;
    final payload = jsonEncode({
      'text': widget.text,
      'baseOffset': widget.selection?.baseOffset ?? widget.text.length,
      'extentOffset': widget.selection?.extentOffset ?? widget.text.length,
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
    if (identical(_activeEditor, this)) _activeEditor = null;
    windowManager.removeListener(this);
    _webFocusNode.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    return Focus(
      focusNode: _webFocusNode,
      canRequestFocus: true,
      onFocusChange: (focused) {
        if (focused && _loaded) {
          _controller?.evaluateJavascript(
            source: 'window.devOrbitRestoreFocus();',
          );
        }
      },
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
  #editor {
    width: 100%; height: 100%; padding: 12px; overflow: auto;
    outline: none; white-space: pre-wrap; overflow-wrap: anywhere;
    tab-size: 2; font: 14px/1.55 Menlo, Consolas, monospace;
    caret-color: currentColor; user-select: text;
  }
  #editor.single-line { white-space: pre; overflow-x: auto; overflow-y: hidden; }
  #editor:empty::before { color: rgba(127, 127, 127, .72); content: attr(data-placeholder); pointer-events: none; }
  .json-key { color: #986801; }
  .json-string { color: #318f4f; }
  .json-number { color: #986801; }
  .json-literal { color: #007fb9; }
  .json-null { color: #a626a4; }
</style>
</head>
<body><div id="editor" contenteditable="true" spellcheck="false"></div>
<script>
const editor = document.getElementById('editor');
let state = { text: '', baseOffset: 0, extentOffset: 0, syntax: 'plain', readOnly: false, findEnabled: false, highlights: [] };
let composing = false;
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
function readText() { return editor.innerText.replace(/\r/g, ''); }
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
  const token = /("(?:\\.|[^"\\])*")|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)|\b(true|false|null)\b/g;
  let html = '', last = 0, match;
  while ((match = token.exec(text))) {
    html += escapeHtml(text.slice(last, match.index));
    const value = match[0], after = text.slice(token.lastIndex);
    let cls = 'json-string';
    if (match[2]) cls = 'json-number';
    if (match[3] === 'null') cls = 'json-null';
    if (match[3] && match[3] !== 'null') cls = 'json-literal';
    if (match[1] && /^\s*:/.test(after)) cls = 'json-key';
    html += '<span class="' + cls + '">' + escapeHtml(value) + '</span>';
    last = token.lastIndex;
  }
  return html + escapeHtml(text.slice(last));
}
function render(text, base, extent, preserve) {
  const saved = preserve ? currentSelection() : [base, extent];
  editor.innerHTML = highlighted(text);
  restoreSelection(preserve ? saved[0] : base, preserve ? saved[1] : extent);
}
window.devOrbitSetState = next => {
  const changedText = next.text !== readText();
  const changedSyntax = state.syntax !== next.syntax;
  state = Object.assign(state, next);
  editor.style.background = next.backgroundColor || '#fbfcfc';
  editor.style.color = next.textColor || '#383a42';
  editor.classList.toggle('single-line', !!next.singleLine);
  editor.dataset.placeholder = next.placeholder || '';
  editor.style.fontSize = (next.fontSize || 14) + 'px';
  const padding = next.padding || {};
  editor.style.padding = `${padding.top ?? 12}px ${padding.right ?? 12}px ${padding.bottom ?? 12}px ${padding.left ?? 12}px`;
  document.documentElement.style.colorScheme = next.isDark ? 'dark' : 'light';
  editor.contentEditable = next.readOnly ? 'false' : 'true';
  if (changedText || changedSyntax) {
    render(next.text, next.baseOffset, next.extentOffset, false);
  } else if (document.activeElement !== editor) {
    // Flutter rebuilds can arrive while a clipboard picker owns the native
    // focus. Do not move the DOM caret to a stale Flutter selection while the
    // editor is temporarily inactive; the window-focus callback restores the
    // saved browser selection after activation.
    lastSelection = [next.baseOffset, next.extentOffset];
  } else {
    restoreSelection(next.baseOffset, next.extentOffset);
  }
};
let lastSelection = [0, 0];
window.devOrbitRestoreFocus = () => {
  editor.focus();
  restoreSelection(lastSelection[0], lastSelection[1]);
};
window.devOrbitFocus = () => {
  editor.focus();
  restoreSelection(lastSelection[0], lastSelection[1]);
};
editor.addEventListener('focus', () => bridge('editorFocusChanged', [true]));
editor.addEventListener('blur', () => bridge('editorFocusChanged', [false]));
editor.addEventListener('compositionstart', () => composing = true);
editor.addEventListener('compositionend', () => { composing = false; editor.dispatchEvent(new Event('input')); });
editor.addEventListener('input', () => {
  if (composing) return;
  const text = readText(), selection = currentSelection();
  lastSelection = selection;
  render(text, selection[0], selection[1], false);
  // Publish the caret before the text callback. Flutter may rebuild the
  // surrounding page from onChanged; having the latest selection already in
  // the controller prevents that rebuild from restoring the previous caret.
  bridge('selectionChanged', selection);
  bridge('editorChanged', [text, selection[0], selection[1]]);
});
document.addEventListener('selectionchange', () => {
  if (document.activeElement !== editor) return;
  const selection = currentSelection();
  lastSelection = selection;
  bridge('selectionChanged', selection);
});
editor.addEventListener('keydown', event => {
  if (state.findEnabled && (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'f') {
    event.preventDefault(); bridge('findRequested', []); return;
  }
  if (event.key === 'Tab') {
    event.preventDefault(); document.execCommand('insertText', false, '  ');
  }
  if (state.singleLine && event.key === 'Enter') {
    event.preventDefault();
  }
});
</script></body></html>''';
