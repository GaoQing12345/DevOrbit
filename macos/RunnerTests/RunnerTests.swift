import Cocoa
import FlutterMacOS
import WebKit
import XCTest
@testable import DevOrbit

private final class TestResponderView: NSView {
  override var acceptsFirstResponder: Bool { true }
}

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testWebViewDescendantResponderDoesNotNeedRecovery() {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    let webView = WKWebView(frame: window.contentView!.bounds)
    let internalResponder = TestResponderView(frame: webView.bounds)
    webView.addSubview(internalResponder)
    window.contentView!.addSubview(webView)

    XCTAssertTrue(
      window.responderBelongsToEditor(webView, responder: internalResponder)
    )
    XCTAssertFalse(
      window.responderBelongsToEditor(webView, responder: window.contentView)
    )
  }

  func testRegisteredEditorKeyResolvesExactWebView() {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    let left = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let right = WKWebView(frame: NSRect(x: 400, y: 0, width: 400, height: 600))
    window.contentView!.addSubview(left)
    window.contentView!.addSubview(right)

    window.registerEditorWebView(left, editorKey: "text-compare-left")
    window.registerEditorWebView(right, editorKey: "text-compare-right")

    XCTAssertTrue(
      window.registeredEditorWebView(for: "text-compare-left") === left
    )
    XCTAssertTrue(
      window.registeredEditorWebView(for: "text-compare-right") === right
    )
  }

}
