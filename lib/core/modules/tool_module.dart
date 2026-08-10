import 'package:flutter/material.dart';

enum ToolLaunchOrigin { radial, toolbox, tray }

class ToolDescriptor {
  const ToolDescriptor({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.radialSlot,
    required this.accentColor,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final int radialSlot;
  final Color accentColor;
}

class ToolLaunchContext {
  const ToolLaunchContext({required this.origin});

  final ToolLaunchOrigin origin;
}

abstract interface class ToolModule {
  ToolDescriptor get descriptor;

  Widget buildPage();

  Future<void> onLaunch(ToolLaunchContext context);
}
