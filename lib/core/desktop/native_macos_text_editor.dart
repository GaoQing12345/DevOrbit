import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A selection reported by the AppKit text view in UTF-16 offsets.
///
/// Dart string offsets use the same UTF-16 indexing model as `NSRange`, so the
/// value can be passed between the two sides without lossy character-count
/// conversions.
@immutable
class NativeTextSelection {
  const NativeTextSelection({
    required this.baseOffset,
    required this.extentOffset,
  });

  final int baseOffset;
  final int extentOffset;

  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;
  int get end => baseOffset > extentOffset ? baseOffset : extentOffset;

  @override
  bool operator ==(Object other) {
    return other is NativeTextSelection &&
        other.baseOffset == baseOffset &&
        other.extentOffset == extentOffset;
  }

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);
}

/// Embeds the macOS AppKit editor registered by the Runner.
///
/// The widget intentionally exposes only text and selection. Search, replace,
/// formatting, and document state remain in Dart, while editing, undo, input
/// methods, and the responder-chain paste action stay native on macOS.
class MacNativeTextEditor extends StatefulWidget {
  const MacNativeTextEditor({
    super.key,
    required this.text,
    required this.selection,
    required this.onChanged,
    required this.onSelectionChanged,
    this.readOnly = false,
    this.backgroundColor,
    this.textColor,
    this.isDark = false,
    this.fontSize = 13,
  });

  final String text;
  final NativeTextSelection selection;
  final ValueChanged<String> onChanged;
  final ValueChanged<NativeTextSelection> onSelectionChanged;
  final bool readOnly;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isDark;
  final double fontSize;

  @override
  State<MacNativeTextEditor> createState() => _MacNativeTextEditorState();
}

class _MacNativeTextEditorState extends State<MacNativeTextEditor> {
  static const _viewType = 'dev_orbit/native_text_editor';

  MethodChannel? _channel;
  bool _disposed = false;

  @override
  void didUpdateWidget(covariant MacNativeTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!Platform.isMacOS) return;
    if (_channel != null && oldWidget.text != widget.text) {
      _invoke('setText', widget.text);
    }
    if (_channel != null && oldWidget.selection != widget.selection) {
      _invoke('setSelection', _selectionArguments(widget.selection));
    }
    if (_channel != null && oldWidget.readOnly != widget.readOnly) {
      _invoke('setEditable', !widget.readOnly);
    }
    if (_channel != null &&
        (oldWidget.isDark != widget.isDark ||
            oldWidget.backgroundColor != widget.backgroundColor ||
            oldWidget.textColor != widget.textColor)) {
      _invoke('setTheme', _themeArguments(context));
    }
  }

  void _onPlatformViewCreated(int viewId) {
    if (!Platform.isMacOS) return;
    final channel = MethodChannel(
      'dev_orbit/native_text_editor/$viewId',
      const StandardMethodCodec(),
    );
    channel.setMethodCallHandler(_handleNativeCall);
    _channel = channel;
    _invoke('setEditable', !widget.readOnly);
    _invoke('setText', widget.text);
    _invoke('setSelection', _selectionArguments(widget.selection));
    _invoke('setTheme', _themeArguments(context));
    _invoke('focus', null);
  }

  Map<String, Object?> _themeArguments(BuildContext context) {
    final theme = Theme.of(context);
    return <String, Object?>{
      'isDark': widget.isDark,
      'backgroundColor':
          (widget.backgroundColor ?? theme.colorScheme.surfaceContainerLowest)
              .toARGB32(),
      'textColor': (widget.textColor ?? theme.colorScheme.onSurface).toARGB32(),
    };
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (_disposed) return null;
    final arguments = call.arguments;
    switch (call.method) {
      case 'textChanged':
        if (arguments is Map && arguments['text'] is String) {
          widget.onChanged(arguments['text'] as String);
          final selection = _decodeSelection(arguments['selection']);
          if (selection != null) widget.onSelectionChanged(selection);
        }
        return null;
      case 'selectionChanged':
        final selection = _decodeSelection(arguments);
        if (selection != null) widget.onSelectionChanged(selection);
        return null;
      default:
        return null;
    }
  }

  NativeTextSelection? _decodeSelection(Object? value) {
    if (value is! Map) return null;
    final baseOffset = value['baseOffset'];
    final extentOffset = value['extentOffset'];
    if (baseOffset is! int || extentOffset is! int) return null;
    return NativeTextSelection(
      baseOffset: baseOffset,
      extentOffset: extentOffset,
    );
  }

  Map<String, int> _selectionArguments(NativeTextSelection selection) {
    return <String, int>{
      'baseOffset': selection.baseOffset,
      'extentOffset': selection.extentOffset,
    };
  }

  void _invoke(String method, Object? arguments) {
    final channel = _channel;
    if (_disposed || channel == null) return;
    channel.invokeMethod<void>(method, arguments).catchError((_) {});
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS || kIsWeb) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return AppKitView(
      viewType: _viewType,
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: <String, Object?>{
        'text': widget.text,
        'editable': !widget.readOnly,
        'fontSize': widget.fontSize,
        'backgroundColor':
            (widget.backgroundColor ?? theme.colorScheme.surfaceContainerLowest)
                .toARGB32(),
        'textColor': (widget.textColor ?? theme.colorScheme.onSurface)
            .toARGB32(),
        'isDark': widget.isDark,
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
