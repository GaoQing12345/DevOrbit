import 'package:flutter/material.dart';

import '../../core/modules/tool_module.dart';
import 'timestamp_page.dart';

class TimestampModule implements ToolModule {
  @override
  ToolDescriptor get descriptor => const ToolDescriptor(
    id: 'timestamp-converter',
    title: '时间戳转换',
    description: '在时间戳和本地日期时间之间快速转换',
    icon: Icons.schedule_rounded,
    radialSlot: 3,
    accentColor: Color(0xFFE05B65),
  );

  @override
  Widget buildPage() => const TimestampPage();

  @override
  Future<void> onLaunch(ToolLaunchContext context) async {}
}
