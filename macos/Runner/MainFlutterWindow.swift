import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  private var cursorChannel: FlutterMethodChannel?
  private var clipboardChannel: FlutterMethodChannel?
  private var credentialsChannel: FlutterMethodChannel?
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
    registerCredentialsChannel(flutterViewController)

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

  private func registerCredentialsChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev_orbit/credentials",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard let arguments = call.arguments as? [String: Any],
            let key = arguments["key"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Missing credential key", details: nil))
        return
      }

      switch call.method {
      case "read":
        do {
          result(try Self.readCredential(key: key))
        } catch let error as NSError {
          result(FlutterError(code: "credential_read_failed", message: error.localizedDescription, details: error.code))
        }
      case "write":
        guard let value = arguments["value"] as? String else {
          result(FlutterError(code: "invalid_arguments", message: "Missing credential value", details: nil))
          return
        }
        do {
          try Self.writeCredential(key: key, value: value)
          result(nil)
        } catch let error as NSError {
          result(FlutterError(code: "credential_write_failed", message: error.localizedDescription, details: error.code))
        }
      case "delete":
        do {
          try Self.deleteCredential(key: key)
          result(nil)
        } catch let error as NSError {
          result(FlutterError(code: "credential_delete_failed", message: error.localizedDescription, details: error.code))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    credentialsChannel = channel
  }

  private static let credentialService = "com.gaoqing.devorbit"

  private static func credentialQuery(key: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: credentialService,
      kSecAttrAccount as String: key,
    ]
  }

  private static func readCredential(key: String) throws -> String? {
    var query = credentialQuery(key: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    if status != errSecSuccess { throw keychainError(status) }
    guard let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func writeCredential(key: String, value: String) throws {
    let query = credentialQuery(key: key)
    let data = Data(value.utf8)
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if updateStatus == errSecSuccess { return }
    if updateStatus != errSecItemNotFound { throw keychainError(updateStatus) }

    var item = query
    item[kSecValueData as String] = data
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    if addStatus != errSecSuccess { throw keychainError(addStatus) }
  }

  private static func deleteCredential(key: String) throws {
    let status = SecItemDelete(credentialQuery(key: key) as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      throw keychainError(status)
    }
  }

  private static func keychainError(_ status: OSStatus) -> NSError {
    let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"
    return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
  }

  deinit {
    if let monitor = pasteKeyMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
