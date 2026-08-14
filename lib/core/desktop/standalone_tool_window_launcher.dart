import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/translator/standalone_translator_constants.dart';
import '../../features/text_compare/standalone_text_compare_constants.dart';
import 'process_window_activator.dart';
import 'single_instance_registry.dart';

const standaloneJsonFormatterFlag = '--json-formatter-window';

typedef DetachedProcessStarter =
    Future<int> Function(String executable, List<String> arguments);
typedef ProcessTerminator = bool Function(int processId);

abstract interface class StandaloneToolWindowLauncher {
  Future<bool> openTool(String toolId);
  Future<void> closeAllTools();
}

class NativeStandaloneToolWindowLauncher
    implements StandaloneToolWindowLauncher {
  NativeStandaloneToolWindowLauncher({
    DetachedProcessStarter? processStarter,
    ProcessTerminator? processTerminator,
    ProcessWindowActivator? windowActivator,
    SingleInstanceRegistry? translatorInstanceRegistry,
    SingleInstanceRegistry? textCompareInstanceRegistry,
    String? executable,
  }) : _processStarter = processStarter ?? _startDetached,
       _processTerminator = processTerminator ?? _terminateProcess,
       _windowActivator = windowActivator ?? NativeProcessWindowActivator(),
       _translatorInstanceRegistry =
           translatorInstanceRegistry ??
           FileSingleInstanceRegistry(translatorInstanceName),
       _textCompareInstanceRegistry =
           textCompareInstanceRegistry ??
           FileSingleInstanceRegistry(textCompareInstanceName),
       _executable = executable ?? Platform.resolvedExecutable;

  static const jsonFormatterId = 'json-formatter';
  static const translatorId = 'translator';
  static const textCompareId = 'text-compare';

  final DetachedProcessStarter _processStarter;
  final ProcessTerminator _processTerminator;
  final ProcessWindowActivator _windowActivator;
  final SingleInstanceRegistry _translatorInstanceRegistry;
  final SingleInstanceRegistry _textCompareInstanceRegistry;
  final String _executable;
  final Map<String, int> _singletonProcessIds = {};
  final Map<String, Future<bool>> _singletonOpens = {};
  final Set<int> _processIds = {};
  final Set<Future<int>> _pendingStarts = {};
  bool _closing = false;

  @override
  Future<bool> openTool(String toolId) async {
    if (_closing) return false;
    try {
      switch (toolId) {
        case jsonFormatterId:
          await _startProcess(const [standaloneJsonFormatterFlag]);
          return true;
        case translatorId:
          return await _openSingleton(
            toolId: translatorId,
            flag: standaloneTranslatorFlag,
            registry: _translatorInstanceRegistry,
          );
        case textCompareId:
          return await _openSingleton(
            toolId: textCompareId,
            flag: standaloneTextCompareFlag,
            registry: _textCompareInstanceRegistry,
          );
        default:
          return false;
      }
    } on ProcessException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _openSingleton({
    required String toolId,
    required String flag,
    required SingleInstanceRegistry registry,
  }) async {
    final pendingOpen = _singletonOpens[toolId];
    if (pendingOpen != null) return await pendingOpen;
    final open = _activateOrStartSingleton(
      toolId: toolId,
      flag: flag,
      registry: registry,
    );
    _singletonOpens[toolId] = open;
    try {
      return await open;
    } finally {
      if (identical(_singletonOpens[toolId], open)) {
        _singletonOpens.remove(toolId);
      }
    }
  }

  Future<bool> _activateOrStartSingleton({
    required String toolId,
    required String flag,
    required SingleInstanceRegistry registry,
  }) async {
    final registeredProcessId = await registry.findProcessId();
    if (registeredProcessId != null && await _activate(registeredProcessId)) {
      _singletonProcessIds[toolId] = registeredProcessId;
      _processIds.add(registeredProcessId);
      return true;
    }
    final processId = _singletonProcessIds[toolId];
    if (processId != null && await _activate(processId)) {
      _processIds.add(processId);
      return true;
    }
    if (_closing) return false;
    _singletonProcessIds[toolId] = await _startProcess([flag]);
    return true;
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
    await _trackRegisteredProcess(_translatorInstanceRegistry);
    await _trackRegisteredProcess(_textCompareInstanceRegistry);
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

  Future<void> _trackRegisteredProcess(SingleInstanceRegistry registry) async {
    try {
      final processId = await registry.findProcessId();
      if (processId != null) _processIds.add(processId);
    } on Object {
      // In-memory tracking is still sufficient for the current app session.
    }
  }

  Future<bool> _activate(int processId) async {
    try {
      return await _windowActivator.activate(processId);
    } on PlatformException {
      return false;
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
