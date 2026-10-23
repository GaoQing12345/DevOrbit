import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../settings/settings_store.dart';
import 'process_window_activator.dart';
import 'single_instance_registry.dart';

/// Claims the single-instance lease for a standalone tool window.
///
/// A second launch activates the window that already owns the lease and exits,
/// so every tool stays a single window.
Future<SingleInstanceLease> acquireStandaloneInstance(
  String instanceName,
) async {
  final registry = FileSingleInstanceRegistry(instanceName);
  final lease = await registry.tryAcquire(pid);
  if (lease != null) return lease;
  try {
    final processId = await registry.findProcessId();
    if (processId != null) {
      await NativeProcessWindowActivator().activate(processId);
    }
  } finally {
    exit(0);
  }
}

/// Prepares the native tool window before the first frame is built.
///
/// Standalone tools are helper windows owned by the main app: they stay out of
/// the Dock and keep the native macOS title bar.
Future<void> prepareStandaloneWindow({
  required Size size,
  required Size minimumSize,
  required String title,
}) async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: size,
      minimumSize: minimumSize,
      center: true,
      skipTaskbar: true,
      title: title,
    ),
  );
  // Each standalone tool is its own process, so it has to read the clipboard
  // diagnostics preference itself; the main window's in-memory flag is not
  // shared across processes.
  await SettingsStore.load();
}
