import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var cursorChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.backgroundColor = NSColor.clear
    self.isOpaque = false
    flutterViewController.backgroundColor = NSColor.clear

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerCursorChannel(flutterViewController)

    super.awakeFromNib()
  }

  private func registerCursorChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev_orbit/cursor",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getCursorScreenPoint" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let mouse = NSEvent.mouseLocation
      let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
      result(["dx": mouse.x, "dy": primaryHeight - mouse.y])
    }
    cursorChannel = channel
  }
}
