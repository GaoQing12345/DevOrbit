import 'dart:async';

import 'package:dev_orbit/core/desktop/process_window_activator.dart';
import 'package:dev_orbit/core/desktop/single_instance_registry.dart';
import 'package:dev_orbit/core/desktop/standalone_tool_window_launcher.dart';
import 'package:dev_orbit/features/translator/standalone_translator_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts a new process for every JSON window request', () async {
    final calls = <(String, List<String>)>[];
    var nextProcessId = 100;
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
        return nextProcessId++;
      },
      windowActivator: _FakeWindowActivator(),
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(),
    );

    expect(await launcher.openTool('json-formatter'), isTrue);
    expect(await launcher.openTool('json-formatter'), isTrue);
    expect(await launcher.openTool('unknown'), isFalse);
    expect(calls, hasLength(2));
    for (final call in calls) {
      expect(call.$1, '/Applications/DevOrbit');
      expect(call.$2, [standaloneJsonFormatterFlag]);
    }
  });

  test('reuses the existing standalone translator window', () async {
    final calls = <(String, List<String>)>[];
    final activator = _FakeWindowActivator(activeProcessIds: {301});
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
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
    var launchCount = 0;
    final launcher = NativeStandaloneToolWindowLauncher(
      processStarter: (_, _) async {
        launchCount++;
        return 602;
      },
      windowActivator: activator,
      translatorInstanceRegistry: _FakeSingleInstanceRegistry(601),
    );

    expect(await launcher.openTool('translator'), isTrue);
    expect(activator.processIds, [601]);
    expect(launchCount, 0);
  });
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

  @override
  Future<int?> findProcessId() async => processId;

  @override
  Future<SingleInstanceLease?> tryAcquire(int processId) async =>
      throw UnimplementedError();
}
