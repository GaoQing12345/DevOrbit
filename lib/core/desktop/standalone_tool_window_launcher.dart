import 'dart:io';

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

  final DetachedProcessStarter _processStarter;
  final String _executable;

  @override
  Future<bool> openTool(String toolId) async {
    if (toolId != jsonFormatterId) return false;
    try {
      await _processStarter(_executable, const [standaloneJsonFormatterFlag]);
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
