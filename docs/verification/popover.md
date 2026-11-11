# Popover positioning verification

The instrumented `7b9e109` baseline failed on its first previous-day navigation: the popover's horizontal range was 0–386 while the status window was at 883–921. See `popover-baseline.jsonl`.

The fix uses a permanent, non-interactive subview of the status button as its anchor. SwiftUI reports natural size through preferences; a plain view controller prevents automatic `preferredContentSize` forwarding. AppDelegate coalesces size changes outside show/close transitions, reapplies the positioning rectangle, and corrects the final window frame in the same pass. Resize/move notifications cover AppKit's deferred window changes, too.

Two findings matter: `NSStatusBarWindow.screen` can be nil, and its reported rectangle can sit above `NSScreen.frame`. The entire popover is therefore constrained to the selected screen's **visible frame**, with its top pinned at `min(icon.minY, visibleFrame.maxY)`. Growing and shrinking derive the bottom from that top, rather than retaining the old bottom-left origin.

```bash
scripts/build-app.sh
dist/LunchBar.app/Contents/MacOS/LunchBar --self-test-popover 360 --right-edge > popover-360-steps.jsonl
```

The hidden test uses a disposable settings suite, the real status item and real NSPopover. It browses dates in both directions, switches breakfast/lunch, expands/collapses rows and toggles favorites. It validates frames after each layout boundary and records each step. `--right-edge` requests the rightmost available application slot using a separate status-item autosave identity; system menu extras still occupy the screen's right end. Owner preferences are retained.

The self-test disables show/close animations and automatic transient dismissal so screenless execution and unrelated desktop interactions cannot stall or close it. Normal use retains those behaviors. The native arrow has no public rendered-edge getter: the test checks top-side anchor geometry, content inset and `hasFullSizeContent == false`; its visual appearance still requires confirmation by eye.

`popover-sized/` contains offscreen renders of the real short-menu view, using the existing `--render-snapshots` path. These are not screen recordings.

Result: **360 steps / 2,880 layout-boundary checks passed**, with 125 growing and 126 shrinking transitions. Content heights: 199, 219, 285, 459, 463, 467 points. The guard fired **507 times**; the underlying AppKit misposition remains observable and is corrected, not claimed eliminated. All 35 existing unit tests passed. The owner should confirm both positioning and native arrow appearance by eye.
