import 'package:flutter/material.dart';

import '../../core/modules/tool_module.dart';
import 'deepl_api_key_store.dart';
import 'deepl_translation_client.dart';
import 'translator_controller.dart';
import 'translator_page.dart';

class TranslatorModule implements ToolModule {
  TranslatorModule()
    : controller = TranslatorController(
        client: DeepLTranslationClient(),
        keyStore: const NativeDeepLApiKeyStore(),
      );

  final TranslatorController controller;

  @override
  ToolDescriptor get descriptor => const ToolDescriptor(
    id: 'translator',
    title: '文本翻译',
    description: '使用 DeepL API Free 快速翻译文本',
    icon: Icons.translate_rounded,
    radialSlot: 1,
    accentColor: Color(0xFF3D7EE8),
  );

  @override
  Widget buildPage() => TranslatorPage(controller: controller);

  @override
  Future<void> onLaunch(ToolLaunchContext context) async {}
}
