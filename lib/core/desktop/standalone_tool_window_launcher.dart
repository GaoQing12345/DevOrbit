import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/translator/standalone_translator_constants.dart';
import '../../features/text_compare/standalone_text_compare_constants.dart';
import 'process_window_activator.dart';
import 'single_instance_registry.dart';

const standaloneJsonFormatterFlag = '--json-formatter-window';
const standaloneJsonFormatterPrewarmFlag = '--json-formatter-prewarm';

typedef DetachedProcessStarter =
    Future<int> Function(String executable, List<String> arguments);
typedef ProcessTerminator = bool Function(int processId);

abstract interface class StandaloneToolWindowLauncher {
  Future<void> warmUp();
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
    bool? enableToolPrewarming,
  }) : _processStarter = processStarter ?? _startDetached,
       _processTerminator = processTerminator ?? _terminateProcess,
       _windowActivator = windowActivator ?? NativeProcessWindowActivator(),
       _translatorInstanceRegistry =
           translatorInstanceRegistry ??
           FileSingleInstanceRegistry(translatorInstanceName),
       _textCompareInstanceRegistry =
           textCompareInstanceRegistry ??
           FileSingleInstanceRegistry(textCompareInstanceName),
       _executable = executable ?? Platform.resolvedExecutable,
       _enableToolPrewarming = enableToolPrewarming ?? Platform.isWindows;

  static const jsonFormatterId = 'json-formatter';
  static const translatorId = 'translator';
  static const textCompareId = 'text-compare';

  final DetachedProcessStarter _processStarter;
  final ProcessTerminator _processTerminator;
  final ProcessWindowActivator _windowActivator;
  final SingleInstanceRegistry _translatorInstanceRegistry;
  final SingleInstanceRegistry _textCompareInstanceRegistry;
  final String _executable;
  final bool _enableToolPrewarming;
  final Map<String, int> _singletonProcessIds = {};
  final Map<String, Future<bool>> _singletonOpens = {};
  final Set<int> _processIds = {};
  final Set<Future<int>> _pendingStarts = {};
  final Map<String, Future<void>> _warmUps = {};
  final Map<String, int> _prewarmedProcessIds = {};
  bool _closing = false;

  @override
  Future<void> warmUp() async {
    if (!_enableToolPrewarming || _closing) return;
    await Future.wait([
      _warmUpTool(
        toolId: jsonFormatterId,
        flag: standaloneJsonFormatterFlag,
        prewarmFlag: standaloneJsonFormatterPrewarmFlag,
      ),
      _warmUpToolAfterDelay(
        delay: const Duration(milliseconds: 120),
        toolId: translatorId,
        flag: standaloneTranslatorFlag,
        prewarmFlag: standaloneTranslatorPrewarmFlag,
        registry: _translatorInstanceRegistry,
      ),
      _warmUpToolAfterDelay(
        delay: const Duration(milliseconds: 240),
        toolId: textCompareId,
        flag: standaloneTextCompareFlag,
        prewarmFlag: standaloneTextComparePrewarmFlag,
        registry: _textCompareInstanceRegistry,
      ),
    ]);
  }

  @override
  Future<bool> openTool(String toolId) async {
    if (_closing) return false;
    try {
      switch (toolId) {
        case jsonFormatterId:
          return await _openJsonFormatter();
        case translatorId:
          return await _openSingleton(
            toolId: translatorId,
            flag: standaloneTranslatorFlag,
            prewarmFlag: standaloneTranslatorPrewarmFlag,
            registry: _translatorInstanceRegistry,
          );
        case textCompareId:
          return await _openSingleton(
            toolId: textCompareId,
            flag: standaloneTextCompareFlag,
            prewarmFlag: standaloneTextComparePrewarmFlag,
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

  Future<void> _warmUpToolAfterDelay({
    required Duration delay,
    required String toolId,
    required String flag,
    required String prewarmFlag,
    SingleInstanceRegistry? registry,
  }) async {
    await Future<void>.delayed(delay);
    await _warmUpTool(
      toolId: toolId,
      flag: flag,
      prewarmFlag: prewarmFlag,
      registry: registry,
    );
  }

  Future<void> _warmUpTool({
    required String toolId,
    required String flag,
    required String prewarmFlag,
    SingleInstanceRegistry? registry,
  }) async {
    if (!_enableToolPrewarming ||
        _closing ||
        _prewarmedProcessIds.containsKey(toolId) ||
        _singletonProcessIds.containsKey(toolId)) {
      return;
    }
    final pending = _warmUps[toolId];
    if (pending != null) return pending;
    final warmUp = _startToolWarmUp(
      toolId: toolId,
      flag: flag,
      prewarmFlag: prewarmFlag,
      registry: registry,
    );
    _warmUps[toolId] = warmUp;
    try {
      await warmUp;
    } on ProcessException {
      return;
    } on FileSystemException {
      return;
    } finally {
      if (identical(_warmUps[toolId], warmUp)) _warmUps.remove(toolId);
    }
  }

  Future<void> _startToolWarmUp({
    required String toolId,
    required String flag,
    required String prewarmFlag,
    SingleInstanceRegistry? registry,
  }) async {
    final registeredProcessId = await registry?.findProcessId();
    if (_closing) return;
    if (registeredProcessId != null) {
      _prewarmedProcessIds[toolId] = registeredProcessId;
      _processIds.add(registeredProcessId);
      return;
    }
    final processId = await _startProcess([flag, prewarmFlag]);
    if (_closing) return;
    if (!_prewarmedProcessIds.containsKey(toolId) &&
        !_singletonProcessIds.containsKey(toolId)) {
      _prewarmedProcessIds[toolId] = processId;
      return;
    }
    _terminateTrackedProcess(processId);
  }

  Future<bool> _openJsonFormatter() async {
    if (!_enableToolPrewarming) {
      await _startProcess(const [standaloneJsonFormatterFlag]);
      return true;
    }
    await _warmUpTool(
      toolId: jsonFormatterId,
      flag: standaloneJsonFormatterFlag,
      prewarmFlag: standaloneJsonFormatterPrewarmFlag,
    );
    final processId = _prewarmedProcessIds.remove(jsonFormatterId);
    if (processId != null && await _activateWithRetry(processId)) {
      unawaited(
        _warmUpTool(
          toolId: jsonFormatterId,
          flag: standaloneJsonFormatterFlag,
          prewarmFlag: standaloneJsonFormatterPrewarmFlag,
        ),
      );
      return true;
    }
    if (processId != null) _terminateTrackedProcess(processId);
    await _startProcess(const [standaloneJsonFormatterFlag]);
    unawaited(
      _warmUpAfterColdStart(
        toolId: jsonFormatterId,
        flag: standaloneJsonFormatterFlag,
        prewarmFlag: standaloneJsonFormatterPrewarmFlag,
      ),
    );
    return true;
  }

  Future<bool> _activateWithRetry(int processId) async {
    const retryDelay = Duration(milliseconds: 25);
    const attempts = 20;
    for (var attempt = 0; attempt < attempts && !_closing; attempt++) {
      if (await _activate(processId)) return true;
      if (attempt + 1 < attempts) await Future<void>.delayed(retryDelay);
    }
    return false;
  }

  Future<void> _warmUpAfterColdStart({
    required String toolId,
    required String flag,
    required String prewarmFlag,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await _warmUpTool(toolId: toolId, flag: flag, prewarmFlag: prewarmFlag);
  }

  Future<bool> _openSingleton({
    required String toolId,
    required String flag,
    required String prewarmFlag,
    required SingleInstanceRegistry registry,
  }) async {
    final pendingOpen = _singletonOpens[toolId];
    if (pendingOpen != null) return await pendingOpen;
    final open = _activateOrStartSingleton(
      toolId: toolId,
      flag: flag,
      prewarmFlag: prewarmFlag,
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
    required String prewarmFlag,
    required SingleInstanceRegistry registry,
  }) async {
    final trackedProcessId = _singletonProcessIds[toolId];
    if (trackedProcessId != null && await _activate(trackedProcessId)) {
      _processIds.add(trackedProcessId);
      return true;
    }
    if (trackedProcessId != null) {
      _singletonProcessIds.remove(toolId);
    }
    await _warmUpTool(
      toolId: toolId,
      flag: flag,
      prewarmFlag: prewarmFlag,
      registry: registry,
    );
    final prewarmedProcessId = _prewarmedProcessIds.remove(toolId);
    if (prewarmedProcessId != null &&
        await _activateWithRetry(prewarmedProcessId)) {
      _singletonProcessIds[toolId] = prewarmedProcessId;
      _processIds.add(prewarmedProcessId);
      return true;
    }
    if (prewarmedProcessId != null) {
      _terminateTrackedProcess(prewarmedProcessId);
    }
    final registeredProcessId = await registry.findProcessId();
    if (registeredProcessId != null &&
        registeredProcessId != prewarmedProcessId &&
        await _activateWithRetry(registeredProcessId)) {
      _singletonProcessIds[toolId] = registeredProcessId;
      _processIds.add(registeredProcessId);
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
    _prewarmedProcessIds.clear();
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

  void _terminateTrackedProcess(int processId) {
    _processIds.remove(processId);
    try {
      _processTerminator(processId);
    } on Object {
      // A failed cleanup must not prevent a fallback window from opening.
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
