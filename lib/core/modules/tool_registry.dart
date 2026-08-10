import 'tool_module.dart';

class ToolRegistry {
  ToolRegistry(List<ToolModule> modules)
    : modules = List.unmodifiable(modules) {
    _validate();
  }

  final List<ToolModule> modules;

  ToolModule byId(String id) {
    return modules.firstWhere((module) => module.descriptor.id == id);
  }

  ToolModule? atSlot(int slot) {
    for (final module in modules) {
      if (module.descriptor.radialSlot == slot) return module;
    }
    return null;
  }

  void _validate() {
    final ids = <String>{};
    final slots = <int>{};
    for (final module in modules) {
      final descriptor = module.descriptor;
      if (!ids.add(descriptor.id)) {
        throw ArgumentError('Duplicate tool id: ${descriptor.id}');
      }
      if (descriptor.radialSlot < 0 || descriptor.radialSlot > 7) {
        throw ArgumentError('Radial slot must be between 0 and 7.');
      }
      if (!slots.add(descriptor.radialSlot)) {
        throw ArgumentError('Duplicate radial slot: ${descriptor.radialSlot}');
      }
    }
  }
}
