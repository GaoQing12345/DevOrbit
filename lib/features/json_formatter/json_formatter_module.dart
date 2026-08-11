import 'package:flutter/material.dart';

import '../../core/modules/tool_module.dart';
import '../../core/settings/settings_store.dart';
import 'json_document_controller.dart';
import 'json_formatter_page.dart';

class JsonFormatterModule implements ToolModule {
  JsonFormatterModule(this.settings) : controller = JsonDocumentController();

  final SettingsStore settings;
  final JsonDocumentController controller;

  @override
  ToolDescriptor get descriptor => const ToolDescriptor(
    id: 'json-formatter',
    title: 'JSON 格式化',
    description: '校验、格式化、压缩并保存严格 JSON',
    icon: Icons.data_object_rounded,
    radialSlot: 0,
    accentColor: Color(0xFF22C7A9),
  );

  @override
  Widget buildPage() {
    return JsonFormatterPage(controller: controller, settings: settings);
  }

  @override
  Future<void> onLaunch(ToolLaunchContext context) async {}
}
