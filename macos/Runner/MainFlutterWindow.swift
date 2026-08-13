import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var cursorChannel: FlutterMethodChannel?
  private var clipboardChannel: FlutterMethodChannel?
  private var pasteKeyMonitor: Any?
  private var pendingPasteText: String?

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
    registerClipboardChannel(flutterViewController)

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

  private func registerClipboardChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev_orbit/clipboard",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getChangeCount":
        result(NSPasteboard.general.changeCount)
      case "takePendingPasteText":
        let text = self?.pendingPasteText
        self?.pendingPasteText = nil
        result(text)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    clipboardChannel = channel
    pasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if flags.contains(.command),
         event.charactersIgnoringModifiers?.lowercased() == "v" {
        self?.pendingPasteText = NSPasteboard.general.string(forType: .string)
      }
      return event
    }
  }

  deinit {
    if let monitor = pasteKeyMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
