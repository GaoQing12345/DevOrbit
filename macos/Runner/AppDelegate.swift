import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var isStandaloneToolWindow: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return arguments.contains("--json-formatter-window") ||
      arguments.contains("--translator-window") ||
      arguments.contains("--text-compare-window")
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
