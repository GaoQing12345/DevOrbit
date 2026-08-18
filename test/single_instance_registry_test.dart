import 'dart:io';

import 'package:dev_orbit/core/desktop/single_instance_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records and releases an instance lease', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dev-orbit-instance-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final registry = FileSingleInstanceRegistry(
      'translator',
      directory: directory,
    );

    final lease = await registry.tryAcquire(7321);

    expect(lease, isNotNull);
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}translator.pid',
      ).readAsString(),
      '7321',
    );

    await lease!.release();
    await lease.release();
    expect(
      File(
        '${directory.path}${Platform.pathSeparator}translator.pid',
      ).existsSync(),
      isFalse,
    );
  });
}
