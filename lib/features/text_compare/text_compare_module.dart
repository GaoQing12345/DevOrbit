import 'package:flutter/material.dart';

import '../../core/modules/tool_module.dart';
import 'text_compare_controller.dart';
import 'text_compare_page.dart';

class TextCompareModule implements ToolModule {
  TextCompareModule() : controller = TextCompareController();

  final TextCompareController controller;

  @override
  ToolDescriptor get descriptor => const ToolDescriptor(
    id: 'text-compare',
    title: '文本比对',
    description: '逐行查看两段文本的新增、删除和修改',
    icon: Icons.difference_rounded,
    radialSlot: 2,
    accentColor: Color(0xFFD18A16),
  );

  @override
  Widget buildPage() => TextComparePage(controller: controller);

  @override
  Future<void> onLaunch(ToolLaunchContext context) async {}
}
