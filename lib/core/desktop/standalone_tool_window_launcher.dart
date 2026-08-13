import 'dart:io';

import '../../features/translator/standalone_translator_app.dart';

const standaloneJsonFormatterFlag = '--json-formatter-window';

typedef DetachedProcessStarter =
    Future<void> Function(String executable, List<String> arguments);

abstract interface class StandaloneToolWindowLauncher {
  Future<bool> openTool(String toolId);
}

class NativeStandaloneToolWindowLauncher
    implements StandaloneToolWindowLauncher {
  NativeStandaloneToolWindowLauncher({
    DetachedProcessStarter? processStarter,
    String? executable,
  }) : _processStarter = processStarter ?? _startDetached,
       _executable = executable ?? Platform.resolvedExecutable;

  static const jsonFormatterId = 'json-formatter';
  static const translatorId = 'translator';

  final DetachedProcessStarter _processStarter;
  final String _executable;

  @override
  Future<bool> openTool(String toolId) async {
    final arguments = switch (toolId) {
      jsonFormatterId => const [standaloneJsonFormatterFlag],
      translatorId => const [standaloneTranslatorFlag],
      _ => null,
    };
    if (arguments == null) return false;
    try {
      await _processStarter(_executable, arguments);
      return true;
    } on ProcessException {
      return false;
    }
  }

  static Future<void> _startDetached(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  }
}
