# Unified Text Compare Find and Focus Design

## Goal

Replace the two independent text-compare find fields with one query that searches both panes, and guarantee that exactly one editing surface owns the caret and paste destination at a time.

## Problem

The text compare page currently combines Flutter `TextField` find inputs with native `WKWebView` editors. Flutter focus, DOM focus, and the AppKit first responder are tracked independently. Moving from a find field to an editor can therefore leave the old Flutter text input client available to AppKit even though normal keyboard input reaches the WebView. The visible result is two apparent carets and `Command+V` inserting into the find field instead of the editor.

Two independent find controllers, focus nodes, match lists, and indices multiply the number of stale states. The current macOS click recovery also repeatedly assigns the outer `WKWebView` as first responder after WebKit has selected its internal editable responder.

## User Experience

- `Command+F` opens one find panel and focuses its single input.
- The query searches both the old-text and new-text panes.
- Navigation starts with the pane that was active when find opened, exhausts that pane in document order, then continues through the other pane.
- Navigation wraps after the final combined match.
- The counter reports the combined position and identifies the current side, for example `左 2/5` or `右 4/5`.
- While the find input owns focus, both editor carets are hidden. A highlighted match may remain visible but is not an editing caret.
- Clicking either editor transfers ownership to that editor in one interaction: the find caret disappears, the clicked editor caret appears, typing and `Command+V` both target it.
- Closing find restores the active result's editor as the sole editing owner while retaining the current match selection.
- Existing clipboard-manager restoration behavior remains available for editor and find input paste operations.

## Architecture

### Unified Find State

`TextComparePage` owns one `TextEditingController`, one `FocusNode`, one ordered list of matches, and one current index. Each match contains its `TextCompareSide`, start offset, and end offset.

The combined match order is rebuilt from the current query and pane contents. If the active side is left, all left matches precede all right matches; if the active side is right, the order is reversed. Opening find captures the active side as the ordering origin. Moving through results changes the active editor side to the selected match without moving keyboard focus out of the find field.

### Exclusive Focus Ownership

The page treats focus ownership as one of three states: find input, left editor, or right editor. Ownership changes only at explicit boundaries:

- Opening or clicking the find input suspends both WebView editor sessions.
- Clicking an editor unfocuses the find input and claims that exact editor session.
- Closing find claims the editor containing the current result, falling back to the last active editor when there is no result.
- Window activation restores only the recorded owner.

The WebView bridge continues to preserve selections while an editor is suspended, but a suspended editor cannot restore native or DOM focus on its own.

### macOS Responder Handling

`MainFlutterWindow` keeps the WebKit responder chosen by the click when that responder is already the clicked WebView or one of its descendants. Recovery assigns the outer `WKWebView` only when the responder is outside the clicked editor and no valid internal responder was established.

The delayed recovery checks ownership before each attempt and never overwrites a valid descendant responder. This keeps key events, edit commands, and the AppKit `paste:` action on the same editor target.

### Paste Routing

The unified find input is registered as a `TextEditingClipboardTarget` while the panel is visible. Editor paste remains owned by the WebView/native path. A transition to an editor clears find ownership before the mouse event completes, so the clipboard restorer cannot reuse the find target for a later editor paste.

Normal clipboard shortcuts and clipboard-manager callbacks must both resolve through the same current ownership state. No fallback may choose a find target merely because it was the most recent Flutter `EditableText`.

## Files

- `lib/features/text_compare/text_compare_page.dart`: unified find state, combined navigation, focus transitions, panel UI, and find-input clipboard target.
- `lib/core/desktop/web_text_editor.dart`: explicit editor claim/suspend behavior needed by the page and responder recovery.
- `macos/Runner/MainFlutterWindow.swift`: preserve WebKit's internal first responder and guard delayed recovery.
- `test/text_compare_page_test.dart`: combined-query ordering, counters, focus transfer, close behavior, and paste ownership regressions.
- `macos/RunnerTests/RunnerTests.swift`: responder selection/recovery regression coverage where it can be isolated from the full Flutter runtime.

## Testing

Tests are written before production changes and must demonstrate the current failure.

- One find field searches and navigates both panes in active-side-first order.
- Reopening find from the other pane reverses only the pane grouping, not document order within a pane.
- Focusing find suspends editor ownership and hides editor carets.
- Clicking an editor removes find focus and makes that editor the only paste target.
- `Command+V` after the focus transfer changes the editor text and leaves the query unchanged.
- Closing find restores the current result's editor.
- Existing text compare, JSON editor, iCopy, selection, IME, and WebView focus tests remain green.
- macOS runner tests verify that a valid responder inside the clicked WebView is not replaced by the outer WebView.

## Constraints

- Do not replace the existing WebView editor.
- Do not change JSON formatter find behavior except where a shared focus fix requires compatible updates.
- Preserve Windows behavior and existing clipboard-manager support.
- Do not introduce timing-based focus retries beyond the existing guarded recovery; ownership checks, not longer delays, determine correctness.
