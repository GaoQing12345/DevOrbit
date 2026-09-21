# Unified Text Compare Find and Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the two text-compare find fields with one cross-pane query and make the find input and WebView editors share one deterministic caret and paste owner.

**Architecture:** `TextComparePage` will hold one query, an ordered cross-pane match list, and an explicit active editor side. Per-editor `DesktopWebTextEditorController` instances will target reveal/focus commands at the correct WebView, while `DesktopClipboardFocusRestorer.clearActiveTarget()` will discard a deliberately abandoned Flutter text target. The macOS runner will preserve WebKit's internal first responder instead of replacing it with the outer `WKWebView`.

**Tech Stack:** Dart 3.12, Flutter widget tests, `flutter_inappwebview`, macOS AppKit/WebKit, XCTest

**Spec:** `docs/superpowers/specs/2026-09-21-unified-text-compare-find-focus-design.md`

## Global Constraints

- Do not replace the existing WebView editor.
- Do not change JSON formatter find behavior except where a shared focus fix requires compatible updates.
- Preserve Windows behavior and existing clipboard-manager support.
- Do not introduce timing-based focus retries beyond the existing guarded recovery; ownership checks, not longer delays, determine correctness.

---

### Task 1: Unified Cross-Pane Find

**Files:**
- Modify: `test/text_compare_page_test.dart`
- Modify: `lib/features/text_compare/text_compare_page.dart`

**Interfaces:**
- Consumes: `TextCompareController.leftText`, `TextCompareController.rightText`, and `TextCompareSide`
- Produces: one `ValueKey('text-compare-find-input')`, one ordered `List<_TextCompareFindMatch>`, and a counter formatted as `左 N/T` or `右 N/T`

- [ ] **Step 1: Replace the dual-find widget test with a failing combined-order test**

Add this test beside the existing `Command+F` test. The production regression it catches is restoring two independent inputs or grouping matches in a fixed left-first order.

```dart
testWidgets('one find input searches the active pane before the other pane', (
  tester,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final controller = TextCompareController(service: _ImmediateService());
  addTearDown(controller.dispose);
  controller.updateLeft('same left same');
  controller.updateRight('same right');

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: TextComparePage(controller: controller))),
  );
  final editors = tester.widgetList<CodeEditor>(find.byType(CodeEditor)).toList();
  editors.last.focusNode!.requestFocus();
  await tester.pump();

  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();

  final input = find.byKey(const ValueKey('text-compare-find-input'));
  expect(input, findsOneWidget);
  expect(find.byKey(const ValueKey('text-compare-right-find-input')), findsNothing);
  await tester.enterText(input, 'same');
  await tester.pump();
  expect(find.text('右 1/3'), findsOneWidget);

  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(find.text('左 2/3'), findsOneWidget);

  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(find.text('左 3/3'), findsOneWidget);

  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(find.text('右 1/3'), findsOneWidget);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
/Users/gaoqing/SDKs/flutter/bin/flutter test test/text_compare_page_test.dart --plain-name "one find input searches the active pane before the other pane"
```

Expected: FAIL because `text-compare-right-find-input` still exists and the current implementation has separate per-side counters.

- [ ] **Step 3: Implement one query and one combined match list**

Change `_TextCompareFindMatch` to carry its side:

```dart
class _TextCompareFindMatch {
  const _TextCompareFindMatch(this.side, this.start, this.end);

  final TextCompareSide side;
  final int start;
  final int end;
}
```

Replace the left/right query fields with:

```dart
late final TextEditingController _findInputController;
final _findFocusNode = FocusNode(debugLabel: 'text-compare-find');
List<_TextCompareFindMatch> _findMatches = const [];
int _findMatchIndex = -1;
TextCompareSide _activeEditorSide = TextCompareSide.left;
TextCompareSide _findStartSide = TextCompareSide.left;
```

Build matches with the captured start side first while preserving document order inside each pane:

```dart
List<_TextCompareFindMatch> _matchesForQuery(String query) {
  if (query.isEmpty) return const [];
  final expression = RegExp(RegExp.escape(query), caseSensitive: false);
  final sides = _findStartSide == TextCompareSide.left
      ? const [TextCompareSide.left, TextCompareSide.right]
      : const [TextCompareSide.right, TextCompareSide.left];
  return [
    for (final side in sides)
      for (final match in expression.allMatches(_findText(side)))
        _TextCompareFindMatch(side, match.start, match.end),
  ];
}
```

Render one `_TextCompareFindPanel` and format its result label from the current match side plus the combined index. Remove all right-find keys, controllers, focus nodes, listeners, lists, and indices.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: PASS with one input and right-first traversal after the right editor was active.

- [ ] **Step 5: Run all text compare tests**

Run:

```bash
/Users/gaoqing/SDKs/flutter/bin/flutter test test/text_compare_page_test.dart
```

Expected: all tests pass. Update the old dual-input expectations to the unified labels without weakening their navigation assertions.

- [ ] **Step 6: Commit the unified find behavior**

```bash
git add lib/features/text_compare/text_compare_page.dart test/text_compare_page_test.dart
git commit -m "fix: unify text compare search"
```

---

### Task 2: Exclusive Focus and Paste Ownership

**Files:**
- Modify: `lib/core/desktop/desktop_clipboard_focus_restorer.dart`
- Modify: `lib/core/desktop/web_text_editor.dart`
- Modify: `lib/features/json_formatter/json_focus_restorer.dart`
- Modify: `lib/features/json_formatter/json_formatter_page.dart`
- Modify: `lib/features/text_compare/text_compare_page.dart`
- Modify: `test/text_compare_page_test.dart`
- Create: `test/desktop_clipboard_target_release_test.dart`

**Interfaces:**
- Produces: `DesktopClipboardFocusRestorer.clearActiveTarget()`
- Produces: `JsonFocusRestorer.clearActiveTarget()`
- Produces: `DesktopWebTextEditorController.revealSelection(NativeTextSelection)` and `restoreFocus()`
- Consumes: one controller per text-compare WebView, passed through `DesktopWebTextEditor.controller`

- [ ] **Step 1: Write a failing clipboard target release test**

Create a widget test with a real `TextField`, `TextEditingClipboardTarget`, and `DesktopClipboardFocusRestorer`. Focus the field, call `clearActiveTarget()`, unfocus it, send `Command+V`, and assert the query text remains unchanged. The production regression it catches is `_lastTarget` silently reviving an intentionally abandoned find field.

```dart
testWidgets('cleared clipboard target cannot receive a later paste', (
  tester,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final controller = TextEditingController(text: 'query');
  final focusNode = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focusNode.dispose);
  final restorer = DesktopClipboardFocusRestorer(
    targets: [
      TextEditingClipboardTarget(controller: controller, focusNode: focusNode),
    ],
  );
  addTearDown(restorer.dispose);
  restorer.active = true;
  mockClipboard(tester, initialText: 'must not enter query');

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: TextField(controller: controller, focusNode: focusNode))),
  );
  focusNode.requestFocus();
  await tester.pump();
  restorer.clearActiveTarget();
  focusNode.unfocus();
  await tester.pump();

  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump(const Duration(milliseconds: 80));

  expect(controller.text, 'query');
});
```

- [ ] **Step 2: Run the target release test and verify RED**

Run:

```bash
/Users/gaoqing/SDKs/flutter/bin/flutter test test/desktop_clipboard_target_release_test.dart
```

Expected: compilation FAIL because `clearActiveTarget()` does not exist.

- [ ] **Step 3: Implement explicit clipboard target release**

Add this public operation to `DesktopClipboardFocusRestorer`:

```dart
void clearActiveTarget() {
  _lastTarget = null;
  _cancelRestore();
}
```

Forward it from `JsonFocusRestorer`, and call it before intentionally transferring from a JSON find field to its WebView. This keeps the shared fix compatible with the existing JSON find panel.

- [ ] **Step 4: Add a failing page-level focus and paste regression test**

Extend `test/text_compare_page_test.dart` with a test that opens find, enters `needle`, activates the right editor, performs a paste through the editor's existing paste action, and asserts the right document changes while the query stays `needle`. Also assert the find `FocusNode.hasFocus` is false after editor activation. The production regression it catches is query ownership surviving the explicit editor transition.

- [ ] **Step 5: Run the page-level test and verify RED**

Run:

```bash
/Users/gaoqing/SDKs/flutter/bin/flutter test test/text_compare_page_test.dart --plain-name "editor activation releases find paste ownership"
```

Expected: FAIL because the current text compare restorer does not include the unified find target and has no explicit target release.

- [ ] **Step 6: Add per-WebView controllers and deterministic handoff**

Introduce `DesktopWebTextEditorController` in `web_text_editor.dart`. It attaches to one `_DesktopWebTextEditorState`, exposes `revealSelection`, and restores only its own editor by claiming the editor session before native and DOM focus recovery.

```dart
class DesktopWebTextEditorController {
  _DesktopWebTextEditorState? _state;

  void revealSelection(NativeTextSelection selection) {
    _state?._revealSelection(selection);
  }

  void restoreFocus() {
    _state?._takeEditorFocus();
  }
}
```

Attach/detach the controller in `initState`, `didUpdateWidget`, and `dispose`. Keep the existing static methods for JSON compatibility, but make text compare use one controller for each side so cross-pane results reveal in the correct editor.

Register the unified find field as a `TextEditingClipboardTarget` with `available: () => _findVisible`. Enable the restorer on desktop WebView builds only while the find field owns the editing session. On editor pointer down, perform this order:

```dart
_focusRestorer.clearActiveTarget();
_findFocusNode.unfocus();
_activeEditorSide = side;
```

Then let `DesktopWebTextEditor._onPointerDown` claim that exact editor session. Closing find calls `restoreFocus()` on the controller for the current match side, or `_activeEditorSide` when there are no matches.

- [ ] **Step 7: Verify GREEN for focus and shared clipboard behavior**

Run:

```bash
/Users/gaoqing/SDKs/flutter/bin/flutter test test/desktop_clipboard_target_release_test.dart test/text_compare_page_test.dart test/json_clipboard_focus_test.dart test/json_third_party_clipboard_test.dart
```

Expected: all tests pass, including existing iCopy/QuickClipboard focus restoration cases.

- [ ] **Step 8: Commit focus ownership changes**

```bash
git add lib/core/desktop/desktop_clipboard_focus_restorer.dart lib/core/desktop/web_text_editor.dart lib/features/json_formatter/json_focus_restorer.dart lib/features/json_formatter/json_formatter_page.dart lib/features/text_compare/text_compare_page.dart test/desktop_clipboard_target_release_test.dart test/text_compare_page_test.dart
git commit -m "fix: make editor focus ownership exclusive"
```

---

### Task 3: Preserve the WebKit Internal First Responder on macOS

**Files:**
- Modify: `macos/Runner/MainFlutterWindow.swift`
- Modify: `macos/RunnerTests/RunnerTests.swift`

**Interfaces:**
- Produces: internal `responderBelongsToEditor(_:responder:) -> Bool`
- Consumes: the clicked `WKWebView` and `NSWindow.firstResponder`

- [ ] **Step 1: Write the failing XCTest for responder ancestry**

Add `import WebKit`, then create a responder-capable descendant view and verify it is recognized as belonging to the clicked WebView:

```swift
private final class TestResponderView: NSView {
  override var acceptsFirstResponder: Bool { true }
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
```

- [ ] **Step 2: Run the runner test and verify RED**

Run when a full Xcode installation is available:

```bash
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS'
```

Expected: compile FAIL because `responderBelongsToEditor` does not exist. If this machine still points at Command Line Tools only, record the exact `xcode-select`/`xcodebuild` failure and continue with Dart verification; do not claim the native test passed.

- [ ] **Step 3: Implement responder ownership checks**

Add an internal helper to `MainFlutterWindow`:

```swift
func responderBelongsToEditor(_ webView: WKWebView, responder: NSResponder?) -> Bool {
  guard let responderView = responder as? NSView else { return false }
  return containingWebView(for: responderView) === webView
}
```

After `super.sendEvent(event)`, return without recovery when the current first responder already belongs to the clicked WebView. Apply the same guard inside every delayed recovery attempt before calling `makeFirstResponder`. Keep the pre-event assignment as a bootstrap for pane switching, but never overwrite the internal responder WebKit establishes while handling the click.

- [ ] **Step 4: Run the runner test and verify GREEN**

Run the Step 2 command. Expected: the new test and existing runner tests pass. If Xcode is unavailable, leave this verification explicitly outstanding and rely only on successful static analysis for Swift syntax that the available toolchain can perform.

- [ ] **Step 5: Commit the native responder fix**

```bash
git add macos/Runner/MainFlutterWindow.swift macos/RunnerTests/RunnerTests.swift
git commit -m "fix: preserve WebKit paste responder"
```

---

### Task 4: Full Regression Verification

**Files:**
- Verify: all files changed in Tasks 1-3

**Interfaces:**
- Consumes: the approved design and every test added above
- Produces: fresh evidence for formatting, analysis, unit tests, and the macOS runner build where the local toolchain permits it

- [ ] **Step 1: Format changed Dart files**

```bash
/Users/gaoqing/SDKs/flutter/bin/dart format lib/core/desktop/desktop_clipboard_focus_restorer.dart lib/core/desktop/web_text_editor.dart lib/features/json_formatter/json_focus_restorer.dart lib/features/json_formatter/json_formatter_page.dart lib/features/text_compare/text_compare_page.dart test/desktop_clipboard_target_release_test.dart test/text_compare_page_test.dart
```

- [ ] **Step 2: Run static analysis**

```bash
/Users/gaoqing/SDKs/flutter/bin/flutter analyze
```

Expected: exit 0 with no errors.

- [ ] **Step 3: Run the complete Flutter test suite**

```bash
/Users/gaoqing/SDKs/flutter/bin/flutter test
```

Expected: all tests pass with zero failures.

- [ ] **Step 4: Run macOS runner tests/build**

```bash
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -destination 'platform=macOS'
```

Expected: runner tests pass. A missing full Xcode installation is an environment limitation to report, not a passing result.

- [ ] **Step 5: Inspect the final diff and repository state**

```bash
git diff --check HEAD~3..HEAD
git status --short --branch
```

Expected: no whitespace errors and no uncommitted implementation files.

- [ ] **Step 6: Perform the manual macOS regression when the app can build**

Run the app, open text compare, open find, type a query, click each editor, type text, and use `Command+V`. Verify visually that only one caret is present and that the query is unchanged after editor paste. Repeat with iCopy once to verify the existing clipboard-manager return path.
