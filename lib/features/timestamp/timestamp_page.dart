import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/desktop/desktop_clipboard_focus_restorer.dart';
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
  late DateTime _now;
  Timer? _clockTimer;
  TimestampConversion? _timestampConversion;
  DateTimeTimestampConversion? _dateTimeConversion;
  String? _timestampError;
  String? _dateTimeError;

  DateTime _readNow() => (widget.now ?? DateTime.now)().toLocal();

  @override
  void initState() {
    super.initState();
    _now = _readNow();
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
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = _readNow());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
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

  void _useCurrentTime() {
    final value = TimestampConverter.formatDateTime(_readNow());
    _dateTimeController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _convertDateTime(value);
    _dateTimeFocusNode.requestFocus();
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
    _focusRestorer.active = Visibility.of(context);
    final current = TimestampConverter.convertDateTime(_now);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          children: [
            _CurrentTimeSection(
              dateTime: TimestampConverter.formatDateTime(_now),
              seconds: current.seconds.toString(),
              milliseconds: current.milliseconds.toString(),
              onCopy: _copyValue,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final timestampPanel = _TimestampToDateTimePanel(
                    controller: _timestampController,
                    focusNode: _timestampFocusNode,
                    conversion: _timestampConversion,
                    error: _timestampError,
                    onChanged: _convertTimestamp,
                    onPaste: _focusRestorer.pasteFocusedTarget,
                    onCopy: _copyValue,
                  );
                  final dateTimePanel = _DateTimeToTimestampPanel(
                    controller: _dateTimeController,
                    focusNode: _dateTimeFocusNode,
                    conversion: _dateTimeConversion,
                    error: _dateTimeError,
                    onChanged: _convertDateTime,
                    onPaste: _focusRestorer.pasteFocusedTarget,
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
    );
  }
}

typedef _CopyCallback = Future<void> Function(String value, String label);

class _CurrentTimeSection extends StatelessWidget {
  const _CurrentTimeSection({
    required this.dateTime,
    required this.seconds,
    required this.milliseconds,
    required this.onCopy,
  });

  final String dateTime;
  final String seconds;
  final String milliseconds;
  final _CopyCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
                onPressed: () => onCopy(dateTime, '本地时间'),
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
                onCopy: () => onCopy(seconds, '秒级时间戳'),
              ),
              _InlineValue(
                label: '毫秒',
                value: milliseconds,
                onCopy: () => onCopy(milliseconds, '毫秒级时间戳'),
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
    required this.onCopy,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TimestampConversion? conversion;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
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
    required this.onUseCurrentTime,
    required this.onCopy,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final DateTimeTimestampConversion? conversion;
  final String? error;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
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
