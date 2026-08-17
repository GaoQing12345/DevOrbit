import 'package:flutter/material.dart';

import '../../core/modules/tool_module.dart';
import 'sql_log_controller.dart';
import 'sql_log_page.dart';

class SqlLogModule implements ToolModule {
  SqlLogModule() : controller = SqlLogController();

  final SqlLogController controller;

  @override
  ToolDescriptor get descriptor => const ToolDescriptor(
    id: 'sql-log-converter',
    title: 'SQL 日志还原',
    description: '提取 MyBatis SQL 并按参数类型还原占位符',
    icon: Icons.storage_rounded,
    radialSlot: 4,
    accentColor: Color(0xFF1A9B7A),
  );

  @override
  Widget buildPage() => SqlLogPage(controller: controller);

  @override
  Future<void> onLaunch(ToolLaunchContext context) async {}
}
