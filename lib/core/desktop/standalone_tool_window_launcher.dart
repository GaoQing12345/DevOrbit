import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/json_formatter/standalone_json_formatter_constants.dart';
import '../../features/sql_log/standalone_sql_log_constants.dart';
import '../../features/text_compare/standalone_text_compare_constants.dart';
import '../../features/timestamp/standalone_timestamp_constants.dart';
import '../../features/translator/standalone_translator_constants.dart';
import 'process_window_activator.dart';
import 'single_instance_registry.dart';

export '../../features/json_formatter/standalone_json_formatter_constants.dart';

typedef DetachedProcessStarter =
    Future<int> Function(String executable, List<String> arguments);
typedef ProcessTerminator = bool Function(int processId);

abstract interface class StandaloneToolWindowLauncher {
  Future<bool> openTool(String toolId);
  Future<void> closeAllTools();
}

/// Launches every tool as its own process and keeps it to a single window.
///
/// macOS names the process per tool `.app` bundle, so a tool window is a real
/// application window owned by the main app: it is always started on demand and
/// never prewarmed, which would keep five hidden processes alive.
class NativeStandaloneToolWindowLauncher
    implements StandaloneToolWindowLauncher {
  NativeStandaloneToolWindowLauncher({
    DetachedProcessStarter? processStarter,
    ProcessTerminator? processTerminator,
    ProcessWindowActivator? windowActivator,
    SingleInstanceRegistry? translatorInstanceRegistry,
    SingleInstanceRegistry? textCompareInstanceRegistry,
    SingleInstanceRegistry? timestampInstanceRegistry,
    SingleInstanceRegistry? sqlLogInstanceRegistry,
    SingleInstanceRegistry? jsonFormatterInstanceRegistry,
    String? executable,
  }) : _processStarter = processStarter ?? _startDetached,
       _processTerminator = processTerminator ?? _terminateProcess,
       _windowActivator = windowActivator ?? NativeProcessWindowActivator(),
       _executable = executable ?? Platform.resolvedExecutable,
       _specs = {
         jsonFormatterId: _ToolSpec(
           flag: standaloneJsonFormatterFlag,
           registry:
               jsonFormatterInstanceRegistry ??
               FileSingleInstanceRegistry(jsonFormatterInstanceName),
         ),
         translatorId: _ToolSpec(
           flag: standaloneTranslatorFlag,
           registry:
               translatorInstanceRegistry ??
               FileSingleInstanceRegistry(translatorInstanceName),
         ),
         textCompareId: _ToolSpec(
           flag: standaloneTextCompareFlag,
           registry:
               textCompareInstanceRegistry ??
               FileSingleInstanceRegistry(textCompareInstanceName),
         ),
         timestampId: _ToolSpec(
           flag: standaloneTimestampFlag,
           registry:
               timestampInstanceRegistry ??
               FileSingleInstanceRegistry(timestampInstanceName),
         ),
         sqlLogId: _ToolSpec(
           flag: standaloneSqlLogFlag,
           registry:
               sqlLogInstanceRegistry ??
               FileSingleInstanceRegistry(sqlLogInstanceName),
         ),
       };

  static const jsonFormatterId = 'json-formatter';
  static const translatorId = 'translator';
  static const textCompareId = 'text-compare';
  static const timestampId = 'timestamp-converter';
  static const sqlLogId = 'sql-log-converter';

  final DetachedProcessStarter _processStarter;
  final ProcessTerminator _processTerminator;
  final ProcessWindowActivator _windowActivator;
  final String _executable;
  final Map<String, _ToolSpec> _specs;
  final Map<String, int> _singletonProcessIds = {};
  final Map<String, Future<bool>> _singletonOpens = {};
  final Set<int> _processIds = {};
  final Set<Future<int>> _pendingStarts = {};
  bool _closing = false;

  @override
  Future<bool> openTool(String toolId) async {
    final spec = _specs[toolId];
    if (_closing || spec == null) return false;
    try {
      return await _openSingleton(toolId, spec);
    } on ProcessException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _openSingleton(String toolId, _ToolSpec spec) async {
    final pendingOpen = _singletonOpens[toolId];
    if (pendingOpen != null) return pendingOpen;
    final open = _activateOrStart(toolId, spec);
    _singletonOpens[toolId] = open;
    try {
      return await open;
    } finally {
      if (identical(_singletonOpens[toolId], open)) {
        _singletonOpens.remove(toolId);
      }
    }
  }

  Future<bool> _activateOrStart(String toolId, _ToolSpec spec) async {
    final trackedProcessId = _singletonProcessIds[toolId];
    if (trackedProcessId != null) {
      if (await _activate(trackedProcessId)) {
        _processIds.add(trackedProcessId);
        return true;
      }
      _singletonProcessIds.remove(toolId);
    }
    // A window left over from an earlier app run still owns the registry entry.
    final registeredProcessId = await spec.registry.findProcessId();
    if (registeredProcessId != null &&
        await _activateWithRetry(registeredProcessId)) {
      _singletonProcessIds[toolId] = registeredProcessId;
      _processIds.add(registeredProcessId);
      return true;
    }
    if (_closing) return false;
    _singletonProcessIds[toolId] = await _startProcess([spec.flag]);
    return true;
  }

  Future<bool> _activateWithRetry(int processId) async {
    const retryDelay = Duration(milliseconds: 25);
    const attempts = 60;
    for (var attempt = 0; attempt < attempts && !_closing; attempt++) {
      if (await _activate(processId)) return true;
      if (attempt + 1 < attempts) await Future<void>.delayed(retryDelay);
    }
    return false;
  }

  Future<int> _startProcess(List<String> arguments) async {
    final pending = _processStarter(_executable, arguments);
    _pendingStarts.add(pending);
    try {
      final processId = await pending;
      _processIds.add(processId);
      return processId;
    } finally {
      _pendingStarts.remove(pending);
    }
  }

  Future<bool> _activate(int processId) async {
    try {
      return await _windowActivator.activate(processId);
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> closeAllTools() async {
    _closing = true;
    final singletonOpens = _singletonOpens.values.toList();
    if (singletonOpens.isNotEmpty) {
      try {
        await Future.wait(singletonOpens);
      } on Object {
        // A failed launch must not prevent the remaining processes closing.
      }
    }
    while (_pendingStarts.isNotEmpty) {
      try {
        await Future.wait(_pendingStarts.toList());
      } on Object {
        // Failed starts remove themselves from the pending set.
      }
    }
    for (final spec in _specs.values) {
      try {
        final processId = await spec.registry.findProcessId();
        if (processId != null) _processIds.add(processId);
      } on Object {
        // In-memory tracking is still sufficient for the current app session.
      }
    }
    final processIds = _processIds.toList();
    _processIds.clear();
    _singletonProcessIds.clear();
    for (final processId in processIds) {
      try {
        _processTerminator(processId);
      } on Object {
        // Continue closing the other standalone windows.
      }
    }
  }

  static Future<int> _startDetached(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }

  static bool _terminateProcess(int processId) => Process.killPid(processId);
}

class _ToolSpec {
  const _ToolSpec({required this.flag, required this.registry});

  /// Command line flag that turns the shared executable into this tool window.
  final String flag;
  final SingleInstanceRegistry registry;
}
