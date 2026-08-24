import 'dart:async';

import 'package:dev_orbit/core/desktop/process_window_activator.dart';
import 'package:dev_orbit/core/desktop/single_instance_registry.dart';
import 'package:dev_orbit/core/desktop/standalone_tool_window_launcher.dart';
import 'package:dev_orbit/features/sql_log/standalone_sql_log_constants.dart';
import 'package:dev_orbit/features/text_compare/standalone_text_compare_constants.dart';
import 'package:dev_orbit/features/timestamp/standalone_timestamp_constants.dart';
import 'package:dev_orbit/features/translator/standalone_translator_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuses the existing standalone JSON formatter window', () async {
    final calls = <(String, List<String>)>[];
    var nextProcessId = 100;
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
      enableToolPrewarming: false,
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
        return nextProcessId++;
      },
      windowActivator: _FakeWindowActivator(activeProcessIds: {100}),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      jsonFormatterInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    expect(await launcher.openTool('json-formatter'), isTrue);
    expect(await launcher.openTool('json-formatter'), isTrue);
    expect(await launcher.openTool('unknown'), isFalse);
    expect(calls, hasLength(1));
    expect(calls.single.$1, '/Applications/DevOrbit');
    expect(calls.single.$2, [standaloneJsonFormatterFlag]);
  });

  test('prewarms and activates every Windows tool', () async {
    final calls = <(String, List<String>)>[];
    var nextProcessId = 901;
    final activator = _FakeWindowActivator(
      activeProcessIds: {901, 902, 903, 904, 905},
    );
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: 'DevOrbit.exe',
      enableToolPrewarming: true,
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
        return nextProcessId++;
      },
      processTerminator: (_) => true,
      windowActivator: activator,
      jsonFormatterInstanceRegistry: _FakeSingleInstanceRegistry(),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
      timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
      sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    await launcher.warmUp();
    expect(calls.map((call) => call.$2), [
      [standaloneJsonFormatterFlag, standaloneJsonFormatterPrewarmFlag],
      [standaloneTranslatorFlag, standaloneTranslatorPrewarmFlag],
      [standaloneTextCompareFlag, standaloneTextComparePrewarmFlag],
      [standaloneTimestampFlag, standaloneTimestampPrewarmFlag],
      [standaloneSqlLogFlag, standaloneSqlLogPrewarmFlag],
    ]);

    expect(await launcher.openTool('json-formatter'), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(await launcher.openTool('translator'), isTrue);
    expect(await launcher.openTool('text-compare'), isTrue);
    expect(await launcher.openTool('timestamp-converter'), isTrue);
    expect(await launcher.openTool('sql-log-converter'), isTrue);

    expect(calls, hasLength(5));
    expect(activator.processIds, [901, 902, 903, 904, 905]);
  });

  test('reuses the existing standalone translator window', () async {
    final calls = <(String, List<String>)>[];
    final activator = _FakeWindowActivator(activeProcessIds: {301});
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
      enableToolPrewarming: false,
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
        return 301;
      },
      windowActivator: activator,
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    expect(await launcher.openTool('translator'), isTrue);
    expect(await launcher.openTool('translator'), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.$2, [standaloneTranslatorFlag]);
    expect(activator.processIds, [301]);
  });

  test('starts a new translator after the previous process exits', () async {
    var nextProcessId = 401;
    final activator = _FakeWindowActivator();
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: false,
      processStarter: (_, _) async => nextProcessId++,
      windowActivator: activator,
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    expect(await launcher.openTool('translator'), isTrue);
    expect(await launcher.openTool('translator'), isTrue);

    expect(activator.processIds, [401]);
    expect(nextProcessId, 403);
  });

  test('coalesces concurrent translator launch requests', () async {
    final launchCompleter = Completer<int>();
    var launchCount = 0;
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: false,
      processStarter: (_, _) {
        launchCount++;
        return launchCompleter.future;
      },
      windowActivator: _FakeWindowActivator(activeProcessIds: {501}),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    final first = launcher.openTool('translator');
    final second = launcher.openTool('translator');
    launchCompleter.complete(501);

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(launchCount, 1);
  });

  test('reuses a translator registered by an earlier main process', () async {
    final activator = _FakeWindowActivator(activeProcessIds: {601});
    final registry = _FakeSingleInstanceRegistry(601);
    var launchCount = 0;
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: false,
      processStarter: (_, _) async {
        launchCount++;
        return 602;
      },
      windowActivator: activator,
      translatorInstanceRegistry: registry,
    );

    expect(await launcher.openTool('translator'), isTrue);
    expect(await launcher.openTool('translator'), isTrue);
    expect(activator.processIds, [601, 601]);
    expect(registry.findCount, 1);
    expect(launchCount, 0);
  });

  test('reuses the existing standalone text compare window', () async {
    final calls = <(String, List<String>)>[];
    final activator = _FakeWindowActivator(activeProcessIds: {651});
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
      enableToolPrewarming: false,
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
        return 651;
      },
      windowActivator: activator,
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    expect(await launcher.openTool('text-compare'), isTrue);
    expect(await launcher.openTool('text-compare'), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.$2, [standaloneTextCompareFlag]);
    expect(activator.processIds, [651]);
  });

  test('coalesces concurrent text compare launch requests', () async {
    final launchCompleter = Completer<int>();
    var launchCount = 0;
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: false,
      processStarter: (_, _) {
        launchCount++;
        return launchCompleter.future;
      },
      windowActivator: _FakeWindowActivator(activeProcessIds: {681}),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    final first = launcher.openTool('text-compare');
    final second = launcher.openTool('text-compare');
    launchCompleter.complete(681);

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(launchCount, 1);
  });

  test('reuses the existing standalone timestamp window', () async {
    final calls = <(String, List<String>)>[];
    final activator = _FakeWindowActivator(activeProcessIds: {691});
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
      enableToolPrewarming: false,
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
        return 691;
      },
      windowActivator: activator,
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
      timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
      sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    expect(await launcher.openTool('timestamp-converter'), isTrue);
    expect(await launcher.openTool('timestamp-converter'), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.$2, [standaloneTimestampFlag]);
    expect(activator.processIds, [691]);
  });

  test('coalesces concurrent timestamp launch requests', () async {
    final launchCompleter = Completer<int>();
    var launchCount = 0;
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: false,
      processStarter: (_, _) {
        launchCount++;
        return launchCompleter.future;
      },
      windowActivator: _FakeWindowActivator(activeProcessIds: {694}),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
      timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
      sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    final first = launcher.openTool('timestamp-converter');
    final second = launcher.openTool('timestamp-converter');
    launchCompleter.complete(694);

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(launchCount, 1);
  });

  test('reuses the existing standalone SQL log window', () async {
    final calls = <(String, List<String>)>[];
    final activator = _FakeWindowActivator(activeProcessIds: {696});
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
      enableToolPrewarming: false,
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
        return 696;
      },
      windowActivator: activator,
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
      timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
      sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    expect(await launcher.openTool('sql-log-converter'), isTrue);
    expect(await launcher.openTool('sql-log-converter'), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.$2, [standaloneSqlLogFlag]);
    expect(activator.processIds, [696]);
  });

  test('coalesces concurrent SQL log launch requests', () async {
    final launchCompleter = Completer<int>();
    var launchCount = 0;
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: false,
      processStarter: (_, _) {
        launchCount++;
        return launchCompleter.future;
      },
      windowActivator: _FakeWindowActivator(activeProcessIds: {698}),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
      timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
      sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    final first = launcher.openTool('sql-log-converter');
    final second = launcher.openTool('sql-log-converter');
    launchCompleter.complete(698);

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(launchCount, 1);
  });

  test('closes every standalone process started by this launcher', () async {
    var nextProcessId = 701;
    final terminated = <int>[];
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: false,
      processStarter: (_, _) async => nextProcessId++,
      processTerminator: (processId) {
        terminated.add(processId);
        return true;
      },
      windowActivator: _FakeWindowActivator(),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
      timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
      sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    await launcher.openTool('json-formatter');
    await launcher.openTool('json-formatter');
    await launcher.openTool('translator');
    await launcher.closeAllTools();

    expect(terminated, [701, 702, 703]);
  });

  test('quit closes every unused prewarmed tool process', () async {
    final terminated = <int>[];
    var nextProcessId = 751;
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: true,
      processStarter: (_, _) async => nextProcessId++,
      processTerminator: (processId) {
        terminated.add(processId);
        return true;
      },
      windowActivator: _FakeWindowActivator(),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
      timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
      sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    await launcher.warmUp();
    await launcher.closeAllTools();

    expect(terminated, [751, 752, 753, 754, 755]);
  });

  test('quit cancels tool prewarming that has not started yet', () async {
    final calls = <List<String>>[];
    final firstStart = Completer<void>();
    final terminated = <int>[];
    var nextProcessId = 801;
    final launcher = NativeStandaloneToolWindowLauncher(
      enableToolPrewarming: true,
      processStarter: (_, arguments) async {
        calls.add(arguments);
        if (!firstStart.isCompleted) firstStart.complete();
        return nextProcessId++;
      },
      processTerminator: (processId) {
        terminated.add(processId);
        return true;
      },
      windowActivator: _FakeWindowActivator(),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
      textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
      timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
      sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    final warming = launcher.warmUp();
    await firstStart.future;
    await launcher.closeAllTools();
    await warming;

    expect(calls, [
      [standaloneJsonFormatterFlag, standaloneJsonFormatterPrewarmFlag],
    ]);
    expect(terminated, [801]);
  });

  test(
    'quit also closes a standalone process that is still starting',
    () async {
      final processStarted = Completer<int>();
      final terminated = <int>[];
      final launcher = NativeStandaloneToolWindowLauncher(
        enableToolPrewarming: false,
        processStarter: (_, _) => processStarted.future,
        processTerminator: (processId) {
          terminated.add(processId);
          return true;
        },
        windowActivator: _FakeWindowActivator(),
        jsonFormatterInstanceRegistry: _FakeSingleInstanceRegistry(),
        translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
        textCompareInstanceRegistry: _FakeSingleInstanceRegistry(),
        timestampInstanceRegistry: _FakeSingleInstanceRegistry(),
        sqlLogInstanceRegistry: _FakeSingleInstanceRegistry(),
      );

      final opening = launcher.openTool('json-formatter');
      await Future<void>.delayed(Duration.zero);
      final closing = launcher.closeAllTools();
      processStarted.complete(801);

      expect(await opening, isTrue);
      await closing;
      expect(terminated, [801]);
    },
  );
}

class _FakeWindowActivator implements ProcessWindowActivator {
  _FakeWindowActivator({this.activeProcessIds = const {}});

  final Set<int> activeProcessIds;
  final List<int> processIds = [];

  @override
  Future<bool> activate(int processId) async {
    processIds.add(processId);
    return activeProcessIds.contains(processId);
  }
}

class _FakeSingleInstanceRegistry implements SingleInstanceRegistry {
  _FakeSingleInstanceRegistry([this.processId]);

  final int? processId;
  int findCount = 0;

  @override
  Future<int?> findProcessId() async {
    findCount++;
    return processId;
  }

  @override
  Future<SingleInstanceLease?> tryAcquire(int processId) async =>
      throw UnimplementedError();
}
