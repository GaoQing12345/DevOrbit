import 'package:dev_orbit/core/modules/tool_module.dart';
import 'package:dev_orbit/core/modules/tool_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds modules by radial slot', () {
    final module = _TestModule(id: 'json', slot: 0);
    final registry = ToolRegistry([module]);

    expect(registry.atSlot(0), same(module));
    expect(registry.atSlot(1), isNull);
  });

  test('rejects duplicate slots', () {
    expect(
      () => ToolRegistry([
        _TestModule(id: 'one', slot: 0),
        _TestModule(id: 'two', slot: 0),
      ]),
      throwsArgumentError,
    );
  });

  test('rejects slots outside the eight-slot ring', () {
    expect(
      () => ToolRegistry([_TestModule(id: 'invalid', slot: 8)]),
      throwsArgumentError,
    );
  });
}

class _TestModule implements ToolModule {
  _TestModule({required this.id, required this.slot});

  final String id;
  final int slot;

  @override
  ToolDescriptor get descriptor => ToolDescriptor(
    id: id,
    title: id,
    description: id,
    icon: Icons.code,
    radialSlot: slot,
    accentColor: Colors.teal,
  );

  @override
  Widget buildPage() => const SizedBox();

  @override
  Future<void> onLaunch(ToolLaunchContext context) async {}
}
