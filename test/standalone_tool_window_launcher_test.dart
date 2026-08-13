import 'package:dev_orbit/core/desktop/standalone_tool_window_launcher.dart';
import 'package:dev_orbit/features/translator/standalone_translator_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts a new process for every JSON window request', () async {
    final calls = <(String, List<String>)>[];
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
      },
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

  test('starts a standalone translator window', () async {
    final calls = <(String, List<String>)>[];
    final launcher = NativeStandaloneToolWindowLauncher(
      executable: '/Applications/DevOrbit',
      processStarter: (executable, arguments) async {
        calls.add((executable, arguments));
      },
    );

    expect(await launcher.openTool('translator'), isTrue);
    expect(calls.single.$2, [standaloneTranslatorFlag]);
  });
}
