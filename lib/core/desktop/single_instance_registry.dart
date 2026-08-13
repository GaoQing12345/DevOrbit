import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

abstract interface class SingleInstanceRegistry {
  Future<int?> findProcessId();

  Future<SingleInstanceLease?> tryAcquire(int processId);
}

abstract interface class SingleInstanceLease {
  Future<void> release();
}

class FileSingleInstanceRegistry implements SingleInstanceRegistry {
  FileSingleInstanceRegistry(
    String name, {
    Directory? directory,
    this.readAttempts = 10,
    this.readDelay = const Duration(milliseconds: 50),
  }) : _lockFile = File(
         path.join((directory ?? Directory.systemTemp).path, '$name.lock'),
       ),
       _processFile = File(
         path.join((directory ?? Directory.systemTemp).path, '$name.pid'),
       );

  final File _lockFile;
  final File _processFile;
  final int readAttempts;
  final Duration readDelay;

  @override
  Future<int?> findProcessId() async {
    final handle = await _lockFile.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      await handle.unlock();
      return null;
    } on FileSystemException {
      return _readProcessId();
    } finally {
      await handle.close();
    }
  }

  @override
  Future<SingleInstanceLease?> tryAcquire(int processId) async {
    final handle = await _lockFile.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
    } on FileSystemException {
      await handle.close();
      return null;
    }

    try {
      await _processFile.writeAsString('$processId', flush: true);
      return _FileSingleInstanceLease(handle, _processFile, processId);
    } on Object {
      await handle.unlock();
      await handle.close();
      rethrow;
    }
  }

  Future<int?> _readProcessId() async {
    for (var attempt = 0; attempt < readAttempts; attempt++) {
      try {
        final value = await _processFile.readAsString();
        final processId = int.tryParse(value.trim());
        if (processId != null) return processId;
      } on FileSystemException {
        // The lock owner may still be writing its process record.
      }
      if (attempt < readAttempts - 1) await Future<void>.delayed(readDelay);
    }
    return null;
  }
}

class _FileSingleInstanceLease implements SingleInstanceLease {
  _FileSingleInstanceLease(this._handle, this._processFile, this._processId);

  final RandomAccessFile _handle;
  final File _processFile;
  final int _processId;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      final recorded = int.tryParse((await _processFile.readAsString()).trim());
      if (recorded == _processId) await _processFile.delete();
    } on FileSystemException {
      // The process record is only a locator; the file lock owns the lease.
    }
    await _handle.unlock();
    await _handle.close();
  }
}
