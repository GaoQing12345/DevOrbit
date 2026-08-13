import 'dart:io';

import 'package:flutter/services.dart';

import '../../features/translator/standalone_translator_constants.dart';
import 'process_window_activator.dart';
import 'single_instance_registry.dart';

const standaloneJsonFormatterFlag = '--json-formatter-window';

typedef DetachedProcessStarter =
    Future<int> Function(String executable, List<String> arguments);

abstract interface class StandaloneToolWindowLauncher {
  Future<bool> openTool(String toolId);
}

class NativeStandaloneToolWindowLauncher
    implements StandaloneToolWindowLauncher {
  NativeStandaloneToolWindowLauncher({
    DetachedProcessStarter? processStarter,
    ProcessWindowActivator? windowActivator,
    SingleInstanceRegistry? translatorInstanceRegistry,
    String? executable,
  }) : _processStarter = processStarter ?? _startDetached,
       _windowActivator = windowActivator ?? NativeProcessWindowActivator(),
       _translatorInstanceRegistry =
           translatorInstanceRegistry ??
           FileSingleInstanceRegistry(translatorInstanceName),
       _executable = executable ?? Platform.resolvedExecutable;

  static const jsonFormatterId = 'json-formatter';
  static const translatorId = 'translator';

  final DetachedProcessStarter _processStarter;
  final ProcessWindowActivator _windowActivator;
  final SingleInstanceRegistry _translatorInstanceRegistry;
  final String _executable;
  int? _translatorProcessId;
  Future<bool>? _translatorOpen;

  @override
  Future<bool> openTool(String toolId) async {
    try {
      switch (toolId) {
        case jsonFormatterId:
          await _processStarter(_executable, const [
            standaloneJsonFormatterFlag,
          ]);
          return true;
        case translatorId:
          final pendingOpen = _translatorOpen;
          if (pendingOpen != null) return await pendingOpen;
          final open = _openTranslator();
          _translatorOpen = open;
          try {
            return await open;
          } finally {
            if (identical(_translatorOpen, open)) {
              _translatorOpen = null;
            }
          }
        default:
          return false;
      }
    } on ProcessException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _openTranslator() async {
    final registeredProcessId = await _translatorInstanceRegistry
        .findProcessId();
    if (registeredProcessId != null && await _activate(registeredProcessId)) {
      _translatorProcessId = registeredProcessId;
      return true;
    }
    final processId = _translatorProcessId;
    if (processId != null && await _activate(processId)) return true;
    _translatorProcessId = await _processStarter(_executable, const [
      standaloneTranslatorFlag,
    ]);
    return true;
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
}
