import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/desktop/desktop_clipboard_focus_restorer.dart';
import '../../core/desktop/desktop_text_selection.dart';
import '../../core/desktop/web_text_editor.dart';
import 'timestamp_converter.dart';

class TimestampPage extends StatefulWidget {
  const TimestampPage({super.key, this.now});

  final DateTime Function()? now;

  @override
  State<TimestampPage> createState() => _TimestampPageState();
}

class _TimestampPageState extends State<TimestampPage> {
  final _timestampController = TextEditingController();
  final _dateTimeController = TextEditingController();
  final _timestampFocusNode = FocusNode();
  final _dateTimeFocusNode = FocusNode();
  late final DesktopClipboardFocusRestorer _focusRestorer;
  TimestampConversion? _timestampConversion;
  DateTimeTimestampConversion? _dateTimeConversion;
  String? _timestampError;
  String? _dateTimeError;

  bool get _usesWebEditor =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows) &&
      Platform.environment['FLUTTER_TEST'] != 'true';

  DateTime _readNow() => (widget.now ?? DateTime.now)().toLocal();

  @override
  void initState() {
    super.initState();
    _focusRestorer = DesktopClipboardFocusRestorer(
      targets: [
        TextEditingClipboardTarget(
          controller: _timestampController,
          focusNode: _timestampFocusNode,
          onChanged: _convertTimestamp,
        ),
        TextEditingClipboardTarget(
          controller: _dateTimeController,
          focusNode: _dateTimeFocusNode,
          onChanged: _convertDateTime,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _focusRestorer.dispose();
    _timestampController.dispose();
    _dateTimeController.dispose();
    _timestampFocusNode.dispose();
    _dateTimeFocusNode.dispose();
    super.dispose();
  }

  void _convertTimestamp(String value) {
    TimestampConversion? conversion;
    String? error;
    if (value.trim().isNotEmpty) {
      try {
        conversion = TimestampConverter.parseTimestamp(value);
      } on FormatException catch (exception) {
        error = exception.message;
      }
    }
    if (!mounted) return;
    setState(() {
      _timestampConversion = conversion;
      _timestampError = error;
    });
  }

  void _convertDateTime(String value) {
    DateTimeTimestampConversion? conversion;
    String? error;
    if (value.trim().isNotEmpty) {
      try {
        conversion = TimestampConverter.convertDateTime(
          TimestampConverter.parseDateTime(value),
        );
      } on FormatException catch (exception) {
        error = exception.message;
      }
    }
    if (!mounted) return;
    setState(() {
      _dateTimeConversion = conversion;
      _dateTimeError = error;
    });
  }

  void _updateWebText(TextEditingController controller, String text) {
    final selection = controller.selection;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
      ),
    );
  }

  void _onTimestampChanged(String value) {
    _updateWebText(_timestampController, value);
    _convertTimestamp(value);
  }

  void _onDateTimeChanged(String value) {
    _updateWebText(_dateTimeController, value);
    _convertDateTime(value);
  }

  void _useCurrentTime() {
    final value = TimestampConverter.formatDateTime(_readNow());
    _dateTimeController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _convertDateTime(value);
    _dateTimeFocusNode.requestFocus();
  }

  NativeTextSelection _selectionFor(TextEditingController controller) {
    final selection = controller.selection;
    return NativeTextSelection(
      baseOffset: selection.baseOffset.clamp(0, controller.text.length),
      extentOffset: selection.extentOffset.clamp(0, controller.text.length),
    );
  }

  void _applySelection(
    TextEditingController controller,
    NativeTextSelection selection,
  ) {
    final length = controller.text.length;
    controller.selection = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, length),
      extentOffset: selection.extentOffset.clamp(0, length),
    );
  }

  Future<void> _pasteInto(
    TextEditingController controller,
    FocusNode focusNode,
  ) async {
    if (!_usesWebEditor) {
      _focusRestorer.pasteFocusedTarget();
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted == null) return;
    final current = controller.text;
    final selection = controller.selection;
    final start = selection.start.clamp(0, current.length);
    final end = selection.end.clamp(start, current.length);
    final next = current.replaceRange(start, end, pasted);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + pasted.length),
    );
    if (identical(controller, _timestampController)) {
      _convertTimestamp(next);
    } else {
      _convertDateTime(next);
    }
    // The browser-backed editor owns focus on desktop. Requesting a Flutter
    // FocusNode here would immediately steal the caret from the WebView.
    if (!_usesWebEditor) focusNode.requestFocus();
  }

  Future<void> _copyValue(String value, String label) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } on PlatformException {
      if (mounted) _showMessage('复制失败');
      return;
    }
    if (mounted) _showMessage('$label已复制');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    _focusRestorer.active = Visibility.of(context) && !_usesWebEditor;
    return DesktopClipboardPasteRegion(
      onPaste: () => _pasteInto(_timestampController, _timestampFocusNode),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            children: [
              _CurrentTimeSection(now: _readNow, onCopy: _copyValue),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final timestampPanel = _TimestampToDateTimePanel(
                      controller: _timestampController,
                      focusNode: _timestampFocusNode,
                      conversion: _timestampConversion,
                      error: _timestampError,
                      onChanged: _onTimestampChanged,
                      onPaste: () =>
                          _pasteInto(_timestampController, _timestampFocusNode),
                      useWebEditor: _usesWebEditor,
                      selection: _selectionFor(_timestampController),
                      onSelectionChanged: (value) =>
                          _applySelection(_timestampController, value),
                      onCopy: _copyValue,
                    );
                    final dateTimePanel = _DateTimeToTimestampPanel(
                      controller: _dateTimeController,
                      focusNode: _dateTimeFocusNode,
                      conversion: _dateTimeConversion,
                      error: _dateTimeError,
                      onChanged: _onDateTimeChanged,
                      onPaste: () =>
                          _pasteInto(_dateTimeController, _dateTimeFocusNode),
                      useWebEditor: _usesWebEditor,
                      selection: _selectionFor(_dateTimeController),
                      onSelectionChanged: (value) =>
                          _applySelection(_dateTimeController, value),
                      onUseCurrentTime: _useCurrentTime,
                      onCopy: _copyValue,
                    );
                    if (constraints.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: timestampPanel),
                          const SizedBox(width: 14),
                          Expanded(child: dateTimePanel),
                        ],
                      );
                    }
                    return ListView(
                      children: [
                        timestampPanel,
                        const SizedBox(height: 14),
                        dateTimePanel,
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _CopyCallback = Future<void> Function(String value, String label);

class _CurrentTimeSection extends StatefulWidget {
  const _CurrentTimeSection({required this.now, required this.onCopy});

  final DateTime Function() now;
  final _CopyCallback onCopy;

  @override
  State<_CurrentTimeSection> createState() => _CurrentTimeSectionState();
}

class _CurrentTimeSectionState extends State<_CurrentTimeSection> {
  late DateTime _now;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _now = widget.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = widget.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = TimestampConverter.convertDateTime(_now);
    final dateTime = TimestampConverter.formatDateTime(_now);
    final seconds = current.seconds.toString();
    final milliseconds = current.milliseconds.toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 12, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前本地时间',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  dateTime,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                tooltip: '复制本地时间',
                onPressed: () => widget.onCopy(dateTime, '本地时间'),
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _InlineValue(
                label: '秒',
                value: seconds,
                onCopy: () => widget.onCopy(seconds, '秒级时间戳'),
              ),
              _InlineValue(
                label: '毫秒',
                value: milliseconds,
                onCopy: () => widget.onCopy(milliseconds, '毫秒级时间戳'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineValue extends StatelessWidget {
  const _InlineValue({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label  ',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SelectableText(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        IconButton(
          tooltip: '复制$label级时间戳',
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded, size: 17),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        ),
      ],
    );
  }
}

class _TimestampToDateTimePanel extends StatelessWidget {
  const _TimestampToDateTimePanel({
    required this.controller,
    required this.focusNode,
    required this.conversion,
    required this.error,
    required this.onChanged,
    required this.onPaste,
    required this.useWebEditor,
    required this.selection,
    required this.onSelectionChanged,
    required this.onCopy,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TimestampConversion? conversion;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final bool useWebEditor;
  final NativeTextSelection selection;
  final ValueChanged<NativeTextSelection> onSelectionChanged;
  final _CopyCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final result = conversion == null
        ? null
        : TimestampConverter.formatDateTime(conversion!.dateTime);
    return _ToolPanel(
      icon: Icons.numbers_rounded,
      title: '时间戳转日期',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              if (useWebEditor)
                SizedBox(
                  height: 58,
                  child: DesktopWebTextEditor(
                    key: const ValueKey('timestamp-input'),
                    text: controller.text,
                    selection: selection,
                    onChanged: onChanged,
                    onSelectionChanged: onSelectionChanged,
                    singleLine: true,
                    placeholder: '1710000000 或 1710000000000',
                    debugLabel: 'timestamp-input',
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerLowest,
                    textColor: Theme.of(context).colorScheme.onSurface,
                    isDark: Theme.of(context).brightness == Brightness.dark,
                    autofocus: true,
                    padding: const EdgeInsets.fromLTRB(14, 18, 52, 10),
                  ),
                )
              else
                TextField(
                  key: const ValueKey('timestamp-input'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  onChanged: onChanged,
                  contextMenuBuilder: (context, editableTextState) =>
                      AdaptiveTextSelectionToolbar.editableText(
                        editableTextState: editableTextState,
                      ),
                  decoration: InputDecoration(
                    labelText: '时间戳',
                    hintText: '1710000000 或 1710000000000',
                    errorText: error,
                    suffixIcon: IconButton(
                      tooltip: '粘贴',
                      onPressed: onPaste,
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                ),
              if (useWebEditor)
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton(
                    tooltip: '粘贴',
                    onPressed: onPaste,
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                ),
            ],
          ),
          if (error != null && useWebEditor)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 14),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 18),
          _ResultBlock(
            label: conversion == null
                ? '本地时间'
                : '本地时间 · 自动识别为${TimestampConverter.unitLabel(conversion!.unit)}',
            value: result,
            onCopy: result == null ? null : () => onCopy(result, '本地时间'),
          ),
        ],
      ),
    );
  }
}

class _DateTimeToTimestampPanel extends StatelessWidget {
  const _DateTimeToTimestampPanel({
    required this.controller,
    required this.focusNode,
    required this.conversion,
    required this.error,
    required this.onChanged,
    required this.onPaste,
    required this.useWebEditor,
    required this.selection,
    required this.onSelectionChanged,
    required this.onUseCurrentTime,
    required this.onCopy,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final DateTimeTimestampConversion? conversion;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final bool useWebEditor;
  final NativeTextSelection selection;
  final ValueChanged<NativeTextSelection> onSelectionChanged;
  final VoidCallback onUseCurrentTime;
  final _CopyCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final seconds = conversion?.seconds.toString();
    final milliseconds = conversion?.milliseconds.toString();
    return _ToolPanel(
      icon: Icons.calendar_month_rounded,
      title: '日期转时间戳',
      trailing: OutlinedButton.icon(
        onPressed: onUseCurrentTime,
        icon: const Icon(Icons.schedule_rounded, size: 17),
        label: const Text('使用当前时间'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              if (useWebEditor)
                SizedBox(
                  height: 58,
                  child: DesktopWebTextEditor(
                    key: const ValueKey('datetime-input'),
                    text: controller.text,
                    selection: selection,
                    onChanged: onChanged,
                    onSelectionChanged: onSelectionChanged,
                    singleLine: true,
                    placeholder: '2026-08-17 14:30:00',
                    debugLabel: 'datetime-input',
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerLowest,
                    textColor: Theme.of(context).colorScheme.onSurface,
                    isDark: Theme.of(context).brightness == Brightness.dark,
                    autofocus: false,
                    padding: const EdgeInsets.fromLTRB(14, 18, 52, 10),
                  ),
                )
              else
                TextField(
                  key: const ValueKey('datetime-input'),
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  contextMenuBuilder: (context, editableTextState) =>
                      AdaptiveTextSelectionToolbar.editableText(
                        editableTextState: editableTextState,
                      ),
                  decoration: InputDecoration(
                    labelText: '本地日期时间',
                    hintText: '2026-08-17 14:30:00',
                    errorText: error,
                    suffixIcon: IconButton(
                      tooltip: '粘贴',
                      onPressed: onPaste,
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                ),
              if (useWebEditor)
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton(
                    tooltip: '粘贴',
                    onPressed: onPaste,
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                ),
            ],
          ),
          if (error != null && useWebEditor)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 14),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 18),
          _ResultBlock(
            label: '秒级时间戳',
            value: seconds,
            onCopy: seconds == null ? null : () => onCopy(seconds, '秒级时间戳'),
          ),
          const SizedBox(height: 10),
          _ResultBlock(
            label: '毫秒级时间戳',
            value: milliseconds,
            onCopy: milliseconds == null
                ? null
                : () => onCopy(milliseconds, '毫秒级时间戳'),
          ),
        ],
      ),
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 286),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 9),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ?trailing,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String? value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.fromLTRB(13, 9, 6, 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  value ?? '—',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: value == null
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '复制',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}
