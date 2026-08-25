import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'native_macos_text_editor.dart';

/// A single browser-backed editing surface shared by macOS and Windows.
///
/// Keeping the input, selection, undo stack, IME and clipboard in one WebView
/// avoids platform-specific responder/focus bridges. The surrounding Flutter
/// page still owns document state and business actions.
class DesktopWebTextEditor extends StatefulWidget {
  const DesktopWebTextEditor({
    super.key,
    required this.text,
    required this.selection,
    required this.onChanged,
    required this.onSelectionChanged,
    required this.onFind,
    this.backgroundColor,
    this.textColor,
    this.isDark = false,
    this.syntax = WebEditorSyntax.plain,
    this.readOnly = false,
  });

  final String text;
  final NativeTextSelection selection;
  final ValueChanged<String> onChanged;
  final ValueChanged<NativeTextSelection> onSelectionChanged;
  final VoidCallback onFind;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isDark;
  final WebEditorSyntax syntax;
  final bool readOnly;

  @override
  State<DesktopWebTextEditor> createState() => _DesktopWebTextEditorState();
}

enum WebEditorSyntax { plain, json }

class _DesktopWebTextEditorState extends State<DesktopWebTextEditor> {
  InAppWebViewController? _controller;
  bool _loaded = false;
  bool _disposed = false;

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
        widget.onSelectionChanged(
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
        widget.onSelectionChanged(
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
        widget.onFind();
        return null;
      },
    );
  }

  int _asInt(Object? value) => value is num ? value.toInt() : 0;

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    _loaded = true;
    _syncState();
    controller.evaluateJavascript(source: 'window.devOrbitFocus();');
  }

  void _syncState() {
    final controller = _controller;
    if (_disposed || !_loaded || controller == null) return;
    final payload = jsonEncode({
      'text': widget.text,
      'baseOffset': widget.selection.baseOffset,
      'extentOffset': widget.selection.extentOffset,
      'readOnly': widget.readOnly,
      'syntax': widget.syntax.name,
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
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    return InAppWebView(
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
      gestureRecognizers: const {},
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
  #editor:empty::before { content: ''; }
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
let state = { text: '', baseOffset: 0, extentOffset: 0, syntax: 'plain', readOnly: false };
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
    if (node === target) { total += localOffset; found = true; return; }
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
}
function readText() { return editor.innerText.replace(/\r/g, ''); }
function highlighted(text) {
  if (state.syntax !== 'json') return escapeHtml(text);
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
  document.documentElement.style.colorScheme = next.isDark ? 'dark' : 'light';
  editor.contentEditable = next.readOnly ? 'false' : 'true';
  if (changedText || changedSyntax) render(next.text, next.baseOffset, next.extentOffset, false);
  else restoreSelection(next.baseOffset, next.extentOffset);
};
window.devOrbitFocus = () => editor.focus();
editor.addEventListener('compositionstart', () => composing = true);
editor.addEventListener('compositionend', () => { composing = false; editor.dispatchEvent(new Event('input')); });
editor.addEventListener('input', () => {
  if (composing) return;
  const text = readText(), selection = currentSelection();
  render(text, selection[0], selection[1], false);
  bridge('editorChanged', [text, selection[0], selection[1]]);
});
document.addEventListener('selectionchange', () => {
  if (document.activeElement !== editor) return;
  const selection = currentSelection(); bridge('selectionChanged', selection);
});
editor.addEventListener('keydown', event => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'f') {
    event.preventDefault(); bridge('findRequested', []); return;
  }
  if (event.key === 'Tab') {
    event.preventDefault(); document.execCommand('insertText', false, '  ');
  }
});
</script></body></html>''';
