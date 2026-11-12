import AppKit
import Testing
@testable import LunchBar

/// Window placement for the states the owner's Mac actually goes through.
/// Frames are in screen coordinates (origin bottom-left), as AppKit reports them.
@Suite("Menu window geometry")
struct PanelGeometryTests {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func autoHidingMenuBarGivesTheSameTopHiddenOrRevealed() {
        // Auto-hide: the visible frame is the whole screen, and the 30 pt status
        // item window sits above the screen while hidden (observed at y 900 and 932)
        // or inside it while revealed.
        let positions = [900.0, 932.0, 870.0, -30.0]
        let tops = positions.map { y in
            PanelGeometry.anchor(icon: NSRect(x: 1063, y: y, width: 38, height: 30), screen: screen, visible: screen).top
        }
        #expect(Set(tops) == [865])
    }

    @Test func visibleMenuBarHangsBelowIt() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 870)
        let anchor = PanelGeometry.anchor(icon: NSRect(x: 1063, y: 870, width: 38, height: 30), screen: screen, visible: visible)
        #expect(anchor.top == 865)
        #expect(anchor.x == 902) // centered on the icon: 1082 - 180
    }

    @Test func notchedDisplayUsesItsTallerMenuBar() {
        let notched = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 945)
        #expect(PanelGeometry.anchor(icon: NSRect(x: 1300, y: 945, width: 38, height: 37), screen: notched, visible: visible).top == 940)
        // Same display with the menu bar hidden.
        #expect(PanelGeometry.anchor(icon: NSRect(x: 1300, y: 982, width: 38, height: 37), screen: notched, visible: notched).top == 940)
    }

    @Test func clampsToTheVisibleFrameNearEdges() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 870)
        let right = PanelGeometry.anchor(icon: NSRect(x: 1410, y: 870, width: 30, height: 30), screen: screen, visible: visible)
        #expect(right.x == 1440 - 360 - PanelGeometry.screenMargin)
        let left = PanelGeometry.anchor(icon: NSRect(x: 0, y: 870, width: 30, height: 30), screen: screen, visible: visible)
        #expect(left.x == PanelGeometry.screenMargin)
    }

    @Test func picksTheDisplayThatShowsTheIcon() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let external = NSRect(x: 1440, y: -200, width: 2560, height: 1440)
        let above = NSRect(x: 0, y: 900, width: 1920, height: 1080)
        // Icon on the external display's menu bar.
        #expect(PanelGeometry.screenIndex(for: NSRect(x: 3800, y: 1210, width: 38, height: 30), frames: [main, external]) == 1)
        // Hidden icon just above the main display, with another display stacked above it:
        // the nearest top edge wins.
        #expect(PanelGeometry.screenIndex(for: NSRect(x: 1063, y: 870, width: 38, height: 30), frames: [main, above]) == 0)
        #expect(PanelGeometry.screenIndex(for: NSRect(x: 1063, y: 1950, width: 38, height: 30), frames: [main, above]) == 1)
    }

    @Test func heightFollowsContentBetweenTheLimits() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(PanelGeometry.height(natural: 186.4, top: 865, visible: visible) == 187)
        #expect(PanelGeometry.height(natural: 20, top: 865, visible: visible) == PanelGeometry.minHeight)
        #expect(PanelGeometry.height(natural: 4000, top: 865, visible: visible) == PanelGeometry.maxHeight)
        // A short screen limits the height to the space under the menu bar.
        let short = NSRect(x: 0, y: 0, width: 1024, height: 400)
        #expect(PanelGeometry.height(natural: 4000, top: 365, visible: short) == 365 - PanelGeometry.screenMargin)
    }
}
