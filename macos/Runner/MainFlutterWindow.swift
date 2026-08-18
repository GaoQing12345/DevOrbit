import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  private var cursorChannel: FlutterMethodChannel?
  private var clipboardChannel: FlutterMethodChannel?
  private var pasteKeyMonitor: Any?
  private var credentialsChannel: FlutterMethodChannel?
  private var processWindowChannel: FlutterMethodChannel?
  private var appLifecycleChannel: FlutterMethodChannel?
  private var pendingPasteText: String?
  private var pasteCaptureSessionId: Int64?
  private var pasteCaptureBaselineChangeCount = 0
  private var pasteCaptureObservedChangeCount: Int?
  private var pasteCaptureArmed = false
  private var pasteRequestPending = false
  private var pasteRequestNotificationSent = false
  private var pasteTargetClientCount = 0

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
    registerProcessWindowChannel(flutterViewController)
    registerAppLifecycleChannel(flutterViewController)

    super.awakeFromNib()
  }

  override func resignKey() {
    if pasteTargetClientCount > 0 &&
       (!pasteCaptureArmed || pasteCaptureSessionId == nil) {
      beginPasteCapture(sessionId: nil)
    }
    super.resignKey()
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
      case "supportsPasteCapture":
        result(true)
      case "registerPasteTarget":
        self?.pasteTargetClientCount += 1
        result(nil)
      case "unregisterPasteTarget":
        if let self {
          self.pasteTargetClientCount = max(0, self.pasteTargetClientCount - 1)
          if self.pasteTargetClientCount == 0 {
            self.resetPasteCapture()
          }
        }
        result(nil)
      case "takePendingPasteText":
        guard let sessionId = Self.clipboardSessionId(from: call) else {
          result(FlutterError(code: "invalid_arguments", message: "Missing clipboard session ID", details: nil))
          return
        }
        result(self?.takePendingPasteText(sessionId: sessionId))
      case "armPasteCapture":
        guard let sessionId = Self.clipboardSessionId(from: call) else {
          result(FlutterError(code: "invalid_arguments", message: "Missing clipboard session ID", details: nil))
          return
        }
        self?.armPasteCapture(sessionId: sessionId)
        result(nil)
      case "didPasteCaptureObserveChange":
        guard let sessionId = Self.clipboardSessionId(from: call) else {
          result(FlutterError(code: "invalid_arguments", message: "Missing clipboard session ID", details: nil))
          return
        }
        result(self?.didPasteCaptureObserveChange(sessionId: sessionId) ?? false)
      case "discardPendingPasteText":
        guard let sessionId = Self.clipboardSessionId(from: call) else {
          result(FlutterError(code: "invalid_arguments", message: "Missing clipboard session ID", details: nil))
          return
        }
        self?.discardPendingPasteText(sessionId: sessionId)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    clipboardChannel = channel
    pasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      guard let self else { return event }
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let isPasteKey = event.keyCode == 9 ||
        event.charactersIgnoringModifiers?.lowercased() == "v"
      guard self.pasteTargetClientCount > 0,
            self.pasteCaptureArmed,
            flags.contains(.command),
            isPasteKey else {
        return event
      }

      // iCopy restores the previous app and sends a synthetic Command+V. Read
      // the text synchronously while that event is being handled; clipboard
      // managers may restore the previous pasteboard value immediately after.
      self.pasteRequestPending = true
      self.capturePasteRequestText()
      return self.notifyPasteRequestedIfReady() ? nil : event
    }
  }

  private static func clipboardSessionId(from call: FlutterMethodCall) -> Int64? {
    guard let arguments = call.arguments as? [String: Any],
          let value = arguments["sessionId"] as? NSNumber else {
      return nil
    }
    return value.int64Value
  }

  private func beginPasteCapture(sessionId: Int64?) {
    resetPasteCapture()
    let pasteboard = NSPasteboard.general
    pasteCaptureArmed = true
    pasteCaptureSessionId = sessionId
    pasteCaptureBaselineChangeCount = pasteboard.changeCount
  }

  private func armPasteCapture(sessionId: Int64) {
    if pasteCaptureArmed {
      if pasteCaptureSessionId == nil {
        pasteCaptureSessionId = sessionId
        return
      }
      if pasteCaptureSessionId == sessionId {
        return
      }
    }
    beginPasteCapture(sessionId: sessionId)
  }

  private func pollPasteboard() {
    guard pasteCaptureArmed else { return }
    let pasteboard = NSPasteboard.general
    let changeCount = pasteboard.changeCount
    guard changeCount != pasteCaptureBaselineChangeCount else { return }
    pasteCaptureObservedChangeCount = changeCount
    guard let text = pasteboard.string(forType: .string) else { return }
    pendingPasteText = text
  }

  private func capturePasteRequestText() {
    let pasteboard = NSPasteboard.general
    pasteCaptureObservedChangeCount = pasteboard.changeCount
    pendingPasteText = pasteboard.string(forType: .string)
  }

  @discardableResult
  private func notifyPasteRequestedIfReady() -> Bool {
    guard pasteRequestPending, !pasteRequestNotificationSent,
          let text = pendingPasteText,
          !text.isEmpty,
          let channel = clipboardChannel else {
      return false
    }
    pasteRequestNotificationSent = true
    var arguments: [String: Any] = ["text": text]
    if let sessionId = pasteCaptureSessionId {
      arguments["sessionId"] = sessionId
    }
    channel.invokeMethod("pasteRequested", arguments: arguments)
    resetPasteCapture()
    return true
  }

  private func takePendingPasteText(sessionId: Int64) -> String? {
    guard pasteCaptureArmed,
          pasteCaptureSessionId == sessionId,
          let text = pendingPasteText else {
      return nil
    }
    resetPasteCapture()
    return text
  }

  private func didPasteCaptureObserveChange(sessionId: Int64) -> Bool {
    guard pasteCaptureArmed, pasteCaptureSessionId == sessionId else {
      return false
    }
    pollPasteboard()
    return pasteCaptureObservedChangeCount != nil
  }

  private func discardPendingPasteText(sessionId: Int64) {
    guard pasteCaptureSessionId == sessionId else { return }
    resetPasteCapture()
  }

  private func resetPasteCapture() {
    pendingPasteText = nil
    pasteCaptureSessionId = nil
    pasteCaptureObservedChangeCount = nil
    pasteCaptureArmed = false
    pasteRequestPending = false
    pasteRequestNotificationSent = false
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

  private func registerProcessWindowChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev_orbit/process_window",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "activate",
            let arguments = call.arguments as? [String: Any],
            let processId = arguments["processId"] as? NSNumber else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let application = NSRunningApplication(
        processIdentifier: pid_t(processId.int32Value)
      ), application.bundleIdentifier == Bundle.main.bundleIdentifier else {
        result(false)
        return
      }
      application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
      result(true)
    }
    processWindowChannel = channel
  }

  private func registerAppLifecycleChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev_orbit/app_lifecycle",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "quit" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
      DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
      }
    }
    appLifecycleChannel = channel
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
