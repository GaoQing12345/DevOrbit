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
  private var pasteFallbackTimer: Timer?
  private var pasteFallbackProbeTimer: Timer?
  private var lastExternalApplicationBundleIdentifier: String?
  private var pasteFallbackEligible = false
  private var workspaceActivationObserver: NSObjectProtocol?

  private static let clipboardManagerBundleIdentifiers: Set<String> = [
    "cn.better365.iCopy",
  ]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.backgroundColor = NSColor.clear
    self.isOpaque = false
    flutterViewController.backgroundColor = NSColor.clear

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerNativeTextEditor(flutterViewController)
    registerCursorChannel(flutterViewController)
    registerClipboardChannel(flutterViewController)
    registerCredentialsChannel(flutterViewController)
    registerProcessWindowChannel(flutterViewController)
    registerAppLifecycleChannel(flutterViewController)

    workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self,
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
              as? NSRunningApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.bundleIdentifier != Bundle.main.bundleIdentifier else {
        return
      }
      self.lastExternalApplicationBundleIdentifier = application.bundleIdentifier
      if let bundleIdentifier = application.bundleIdentifier {
        self.pasteFallbackEligible = self.pasteCaptureArmed &&
          Self.clipboardManagerBundleIdentifiers.contains(bundleIdentifier)
      } else {
        self.pasteFallbackEligible = false
      }
    }

    super.awakeFromNib()
  }

  private func registerNativeTextEditor(_ controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "DevOrbitNativeTextEditor")
    registrar.register(
      NativeTextEditorFactory(messenger: registrar.messenger),
      withId: "dev_orbit/native_text_editor"
    )
  }

  override func becomeKey() {
    super.becomeKey()
    scheduleClipboardManagerPasteFallback()
  }

  override func resignKey() {
    if pasteTargetClientCount > 0 &&
       (!pasteCaptureArmed || pasteCaptureSessionId == nil) {
      beginPasteCapture(sessionId: nil)
    }
    super.resignKey()
    captureClipboardManagerPasteSource()
    pasteFallbackProbeTimer?.invalidate()
    pasteFallbackProbeTimer = Timer.scheduledTimer(
      withTimeInterval: 0.08,
      repeats: false
    ) { [weak self] _ in
      self?.captureClipboardManagerPasteSource()
    }
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
      case "setDiagnosticsEnabled":
        result(nil)
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
        result(self?.armPasteCapture(sessionId: sessionId) ?? false)
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
      return self.notifyPasteRequestedIfReady(source: "key_event") ? nil : event
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

  private func scheduleClipboardManagerPasteFallback() {
    pasteFallbackTimer?.invalidate()
    pasteFallbackTimer = nil
    guard pasteTargetClientCount > 0,
          pasteCaptureArmed,
          pasteFallbackEligible,
          let bundleIdentifier = lastExternalApplicationBundleIdentifier,
          Self.clipboardManagerBundleIdentifiers.contains(bundleIdentifier) else {
      return
    }

    // iCopy normally sends a synthetic Command+V after it activates the
    // previous app. Occasionally that key event is lost while the Flutter
    // window is becoming key. Give the normal monitor a short head start, then
    // use the changed pasteboard value as a narrowly-scoped fallback.
    pasteFallbackTimer = Timer.scheduledTimer(
      withTimeInterval: 0.12,
      repeats: false
    ) { [weak self] _ in
      self?.deliverClipboardManagerPasteFallback()
    }
  }

  private func captureClipboardManagerPasteSource() {
    guard pasteTargetClientCount > 0, pasteCaptureArmed else { return }

    // iCopy is a UIElement application, so opening its panel does not always
    // emit NSWorkspace.didActivateApplicationNotification. Check both the
    // frontmost app and the running app's active state while our window is
    // resigning key; the latter is the signal available during that popup.
    if let bundleIdentifier = activeClipboardManagerBundleIdentifier() {
      lastExternalApplicationBundleIdentifier = bundleIdentifier
      pasteFallbackEligible = true
      return
    }

    if let application = NSWorkspace.shared.frontmostApplication,
       application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
       let bundleIdentifier = application.bundleIdentifier {
      lastExternalApplicationBundleIdentifier = bundleIdentifier
      pasteFallbackEligible = Self.clipboardManagerBundleIdentifiers.contains(
        bundleIdentifier
      )
    } else {
      pasteFallbackEligible = false
    }
  }

  private func activeClipboardManagerBundleIdentifier() -> String? {
    if let frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?
      .bundleIdentifier,
       Self.clipboardManagerBundleIdentifiers.contains(frontmostBundleIdentifier) {
      return frontmostBundleIdentifier
    }
    for bundleIdentifier in Self.clipboardManagerBundleIdentifiers {
      if NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ).contains(where: { $0.isActive }) {
        return bundleIdentifier
      }
    }
    return nil
  }

  private func deliverClipboardManagerPasteFallback() {
    pasteFallbackTimer = nil
    guard pasteTargetClientCount > 0,
          pasteCaptureArmed,
          pasteFallbackEligible,
          let bundleIdentifier = lastExternalApplicationBundleIdentifier,
          Self.clipboardManagerBundleIdentifiers.contains(bundleIdentifier) else {
      return
    }
    pasteRequestPending = true
    capturePasteRequestText()
    if !notifyPasteRequestedIfReady(source: "focus_fallback") {
      // Do not leave a stale pending request armed if iCopy only opened and
      // closed without changing the clipboard.
      pasteRequestPending = false
    }
  }

  private func armPasteCapture(sessionId: Int64) -> Bool {
    guard pasteTargetClientCount > 0 else {
      resetPasteCapture()
      return false
    }
    if pasteCaptureArmed {
      if pasteCaptureSessionId == nil {
        pasteCaptureSessionId = sessionId
        return true
      }
      if pasteCaptureSessionId == sessionId {
        return true
      }
    }
    beginPasteCapture(sessionId: sessionId)
    return false
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
    let changeCount = pasteboard.changeCount
    // A normal Command+V may arrive while the captured clipboard value is
    // still current. Avoid synchronously asking the pasteboard daemon for the
    // full string in that case; Flutter can handle the unchanged clipboard
    // through its regular paste path. iCopy selections change the count before
    // sending their synthetic Command+V and still take the fast capture path.
    guard changeCount != pasteCaptureBaselineChangeCount else {
      pasteCaptureObservedChangeCount = nil
      return
    }
    pasteCaptureObservedChangeCount = changeCount
    pendingPasteText = pasteboard.string(forType: .string)
  }

  @discardableResult
  private func notifyPasteRequestedIfReady(source: String) -> Bool {
    guard pasteRequestPending, !pasteRequestNotificationSent,
          let text = pendingPasteText,
          !text.isEmpty,
          let channel = clipboardChannel else {
      return false
    }
    pasteRequestNotificationSent = true
    var arguments: [String: Any] = ["text": text, "source": source]
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
    pasteFallbackTimer?.invalidate()
    pasteFallbackTimer = nil
    pasteFallbackProbeTimer?.invalidate()
    pasteFallbackProbeTimer = nil
    pasteFallbackEligible = false
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
    pasteFallbackTimer?.invalidate()
    pasteFallbackProbeTimer?.invalidate()
    if let observer = workspaceActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    if let monitor = pasteKeyMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}

private final class NativeTextEditorFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withViewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> NSView {
    NativeTextEditorView(
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class NativeTextEditorView: NSView, NSTextViewDelegate {
  private let textView: NSTextView
  private let scrollView: NSScrollView
  private let channel: FlutterMethodChannel
  private var windowObservers: [NSObjectProtocol] = []
  private var suppressCallbacks = false
  private var restoreFocusOnWindowActivation = false
  private var isDark = false
  private var backgroundColor = NSColor.textBackgroundColor
  private var textColor = NSColor.textColor

  init(viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    let parameters = arguments as? [String: Any]
    let initialText = parameters?["text"] as? String ?? ""
    let editable = (parameters?["editable"] as? NSNumber)?.boolValue ?? true
    let fontSize = (parameters?["fontSize"] as? NSNumber)?.doubleValue ?? 13
    let backgroundColor = Self.color(
      from: parameters?["backgroundColor"],
      fallback: .textBackgroundColor
    )
    let textColor = Self.color(from: parameters?["textColor"], fallback: .textColor)
    let isDark = (parameters?["isDark"] as? NSNumber)?.boolValue ?? false

    let textView = NSTextView(frame: .zero)
    textView.string = initialText
    textView.isEditable = editable
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindPanel = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    textView.textColor = textColor
    textView.insertionPointColor = textColor
    textView.backgroundColor = backgroundColor
    textView.drawsBackground = true
    textView.textContainerInset = NSSize(width: 12, height: 10)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )

    let scrollView = NSScrollView(frame: .zero)
    scrollView.drawsBackground = true
    scrollView.backgroundColor = backgroundColor
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder
    scrollView.documentView = textView

    self.textView = textView
    self.scrollView = scrollView
    self.channel = FlutterMethodChannel(
      name: "dev_orbit/native_text_editor/\(viewId)",
      binaryMessenger: messenger
    )
    self.backgroundColor = backgroundColor
    self.textColor = textColor
    self.isDark = isDark
    super.init(frame: .zero)

    wantsLayer = true
    layer?.backgroundColor = backgroundColor.cgColor
    textView.delegate = self
    applySyntaxHighlighting()
    addSubview(scrollView)
    windowObservers = [
      NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.windowDidResignKey(notification)
      },
      NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        self?.windowDidBecomeKey(notification)
      },
    ]
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("NativeTextEditorView does not support NSCoder initialization")
  }

  override var acceptsFirstResponder: Bool { true }

  override func becomeFirstResponder() -> Bool {
    window?.makeFirstResponder(textView) ?? false
  }

  override func layout() {
    super.layout()
    scrollView.frame = bounds
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setText":
      guard let text = call.arguments as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Expected text", details: nil))
        return
      }
      setText(text)
      result(nil)
    case "setSelection":
      guard let arguments = call.arguments as? [String: Any],
            let baseOffset = (arguments["baseOffset"] as? NSNumber)?.intValue,
            let extentOffset = (arguments["extentOffset"] as? NSNumber)?.intValue else {
        result(FlutterError(code: "invalid_arguments", message: "Expected selection", details: nil))
        return
      }
      setSelection(baseOffset: baseOffset, extentOffset: extentOffset)
      result(nil)
    case "setEditable":
      if let editable = (call.arguments as? NSNumber)?.boolValue {
        textView.isEditable = editable
      }
      result(nil)
    case "setTheme":
      guard let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Expected theme", details: nil))
        return
      }
      let nextBackgroundColor = Self.color(
        from: arguments["backgroundColor"],
        fallback: backgroundColor
      )
      let nextTextColor = Self.color(from: arguments["textColor"], fallback: textColor)
      isDark = (arguments["isDark"] as? NSNumber)?.boolValue ?? isDark
      backgroundColor = nextBackgroundColor
      textColor = nextTextColor
      textView.backgroundColor = nextBackgroundColor
      textView.insertionPointColor = nextTextColor
      scrollView.backgroundColor = nextBackgroundColor
      layer?.backgroundColor = nextBackgroundColor.cgColor
      applySyntaxHighlighting()
      result(nil)
    case "focus":
      restoreNativeFocus()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setText(_ text: String) {
    guard textView.string != text else { return }
    suppressCallbacks = true
    let selectedRange = textView.selectedRange()
    textView.string = text
    let maxOffset = (text as NSString).length
    let offset = min(selectedRange.location, maxOffset)
    textView.setSelectedRange(NSRange(location: offset, length: 0))
    applySyntaxHighlighting()
    suppressCallbacks = false
  }

  private func setSelection(baseOffset: Int, extentOffset: Int) {
    let maxOffset = (textView.string as NSString).length
    let base = min(max(baseOffset, 0), maxOffset)
    let extent = min(max(extentOffset, 0), maxOffset)
    let location = min(base, extent)
    let length = abs(extent - base)
    suppressCallbacks = true
    textView.setSelectedRange(NSRange(location: location, length: length))
    suppressCallbacks = false
  }

  func textDidChange(_ notification: Notification) {
    guard !suppressCallbacks else { return }
    applySyntaxHighlighting()
    channel.invokeMethod("textChanged", arguments: [
      "text": textView.string,
      "selection": selectionPayload(),
    ])
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    guard !suppressCallbacks else { return }
    channel.invokeMethod("selectionChanged", arguments: selectionPayload())
  }

  private func selectionPayload() -> [String: Int] {
    let range = textView.selectedRange()
    return [
      "baseOffset": range.location,
      "extentOffset": range.location + range.length,
    ]
  }

  private func applySyntaxHighlighting() {
    let string = textView.string
    let attributed = NSMutableAttributedString(
      string: string,
      attributes: [
        .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: textColor,
      ]
    )
    let fullRange = NSRange(location: 0, length: (string as NSString).length)
    guard fullRange.length > 0 else {
      textView.typingAttributes = [
        .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: textColor,
      ]
      textView.textStorage?.setAttributedString(attributed)
      return
    }

    let stringPattern = #"\"(?:\\.|[^\"\\])*\""#
    let numberPattern = #"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#
    let literalPattern = #"\b(?:true|false|null)\b"#
    applyMatches(
      pattern: stringPattern,
      in: string,
      to: attributed,
      color: isDark ? Self.color(red: 0.60, green: 0.76, blue: 0.47) : Self.color(red: 0.31, green: 0.63, blue: 0.31),
      keyColor: isDark ? Self.color(red: 0.90, green: 0.65, blue: 0.34) : Self.color(red: 0.60, green: 0.41, blue: 0.00)
    )
    applyMatches(
      pattern: numberPattern,
      in: string,
      to: attributed,
      color: isDark ? Self.color(red: 0.82, green: 0.64, blue: 0.40) : Self.color(red: 0.60, green: 0.41, blue: 0.00)
    )
    applyMatches(
      pattern: literalPattern,
      in: string,
      to: attributed,
      color: isDark ? Self.color(red: 0.34, green: 0.71, blue: 0.76) : Self.color(red: 0.00, green: 0.52, blue: 0.73),
      nullColor: isDark ? Self.color(red: 0.78, green: 0.47, blue: 0.86) : Self.color(red: 0.65, green: 0.15, blue: 0.64)
    )
    textView.typingAttributes = [
      .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
      .foregroundColor: textColor,
    ]
    textView.textStorage?.setAttributedString(attributed)
  }

  private func applyMatches(
    pattern: String,
    in string: String,
    to attributed: NSMutableAttributedString,
    color: NSColor,
    keyColor: NSColor? = nil,
    nullColor: NSColor? = nil
  ) {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
    let range = NSRange(location: 0, length: (string as NSString).length)
    expression.enumerateMatches(in: string, range: range) { match, _, _ in
      guard let match else { return }
      let token = (string as NSString).substring(with: match.range)
      var tokenColor = color
      if token == "null", let nullColor {
        tokenColor = nullColor
      } else if keyColor != nil && Self.isObjectKey(token, in: string, range: match.range) {
        tokenColor = keyColor!
      }
      attributed.addAttribute(.foregroundColor, value: tokenColor, range: match.range)
    }
  }

  private static func isObjectKey(_ token: String, in string: String, range: NSRange) -> Bool {
    let nsString = string as NSString
    let end = range.location + range.length
    var index = end
    while index < nsString.length {
      let character = nsString.character(at: index)
      if character == 32 || character == 9 || character == 10 || character == 13 {
        index += 1
        continue
      }
      return character == 58
    }
    return false
  }

  private static func color(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
  }

  private func windowDidResignKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === self.window else { return }
    restoreFocusOnWindowActivation = window.firstResponder === textView
  }

  private func windowDidBecomeKey(_ notification: Notification) {
    guard restoreFocusOnWindowActivation,
          let window = notification.object as? NSWindow,
          window === self.window else { return }
    restoreFocusOnWindowActivation = false
    restoreNativeFocus()
  }

  private func restoreNativeFocus(attempt: Int = 0) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let window = self.window, window.isKeyWindow else { return }
      if window.makeFirstResponder(self.textView) {
        window.invalidateCursorRects(for: self.textView)
        return
      }
      guard attempt < 4 else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.restoreNativeFocus(attempt: attempt + 1)
      }
    }
  }

  private static func color(from value: Any?, fallback: NSColor) -> NSColor {
    guard let raw = (value as? NSNumber)?.uint32Value else { return fallback }
    let alpha = CGFloat((raw >> 24) & 0xff) / 255
    let red = CGFloat((raw >> 16) & 0xff) / 255
    let green = CGFloat((raw >> 8) & 0xff) / 255
    let blue = CGFloat(raw & 0xff) / 255
    return NSColor(
      calibratedRed: red,
      green: green,
      blue: blue,
      alpha: alpha
    )
  }

  deinit {
    for observer in windowObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
