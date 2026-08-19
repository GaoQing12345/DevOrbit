import 'package:dev_orbit/core/settings/settings_store.dart';
import 'package:dev_orbit/features/json_formatter/json_document_controller.dart';
import 'package:dev_orbit/features/json_formatter/json_formatter_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets(
      'hidden editor registers no native clipboard target on ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        SharedPreferences.setMockInitialValues({});
        const channel = MethodChannel('dev_orbit/clipboard');
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final settings = await SettingsStore.load();
        final controller = JsonDocumentController();
        addTearDown(settings.dispose);
        addTearDown(controller.dispose);

        Widget buildPage({
          required bool appVisible,
          required bool pageVisible,
        }) => MaterialApp(
          home: Visibility(
            visible: appVisible,
            maintainState: true,
            child: Visibility(
              visible: pageVisible,
              maintainState: true,
              child: Scaffold(
                body: JsonFormatterPage(
                  controller: controller,
                  settings: settings,
                ),
              ),
            ),
          ),
        );

        await tester.pumpWidget(
          buildPage(appVisible: true, pageVisible: false),
        );
        await tester.pump();
        expect(
          calls.where((method) => method == 'registerPasteTarget'),
          isEmpty,
        );

        await tester.pumpWidget(buildPage(appVisible: true, pageVisible: true));
        await tester.pump();
        expect(
          calls.where((method) => method == 'registerPasteTarget'),
          hasLength(1),
        );

        await tester.pumpWidget(
          buildPage(appVisible: false, pageVisible: true),
        );
        await tester.pump();
        expect(
          calls.where((method) => method == 'unregisterPasteTarget'),
          hasLength(1),
        );

        await tester.pumpWidget(
          buildPage(appVisible: false, pageVisible: false),
        );
        await tester.pump();
        expect(
          calls.where((method) => method == 'registerPasteTarget'),
          hasLength(1),
        );
        expect(
          calls.where((method) => method == 'unregisterPasteTarget'),
          hasLength(1),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
