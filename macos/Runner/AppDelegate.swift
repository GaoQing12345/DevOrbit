import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var isStandaloneToolWindow: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return arguments.contains("--json-formatter-window") ||
      arguments.contains("--translator-window") ||
      arguments.contains("--text-compare-window") ||
      arguments.contains("--timestamp-window") ||
      arguments.contains("--sql-log-window")
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Standalone tools are auxiliary windows owned by DevOrbit. Keeping each
    // helper process out of the Dock avoids one icon per tool window.
    if isStandaloneToolWindow {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  override func applicationWillBecomeActive(_ notification: Notification) {
    super.applicationWillBecomeActive(notification)
    restoreStandaloneWindow()
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    super.applicationDidBecomeActive(notification)
    restoreStandaloneWindow()
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    restoreStandaloneWindow()
    return true
  }

  private func restoreStandaloneWindow() {
    guard isStandaloneToolWindow else { return }
    DispatchQueue.main.async {
      NSApp.unhide(nil)
      for window in NSApp.windows where window.isMiniaturized {
        window.deminiaturize(nil)
      }
      if let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) {
        window.makeKeyAndOrderFront(nil)
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return isStandaloneToolWindow
  }

  override func applicationWillTerminate(_ notification: Notification) {
    if !isStandaloneToolWindow,
       let bundleIdentifier = Bundle.main.bundleIdentifier {
      let currentProcessId = ProcessInfo.processInfo.processIdentifier
      for application in NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ) where application.processIdentifier != currentProcessId {
        application.forceTerminate()
      }
    }
    super.applicationWillTerminate(notification)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
