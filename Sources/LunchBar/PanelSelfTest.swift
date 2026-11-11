import AppKit
import LunchKit
import SwiftUI

/// Measures the panel's natural height independently of the live window: lays the
/// content out once more without a scroll view and asks for its fitting size.
@MainActor
enum PanelMeasure {
    static func naturalHeight(model: MenuViewModel, appearance: NSAppearance.Name? = nil) -> CGFloat {
        let hosting = NSHostingView(rootView: PanelView(model: model, openSettings: {}, quit: {}, measuring: true))
        if let appearance { hosting.appearance = NSAppearance(named: appearance) }
        hosting.frame = NSRect(x: 0, y: 0, width: PanelGeometry.width, height: 200)
        hosting.layoutSubtreeIfNeeded()
        return ceil(hosting.fittingSize.height)
    }
}

/// Drives the real status item and menu window through hundreds of content
/// changes and checks the window geometry after each one. Writes JSON lines to
/// stdout and exits nonzero on the first violation.
///
///     LunchBar --self-test-panel [steps] [--no-animation] [--right-edge]
///
/// Uses a disposable settings suite, so the owner's places and favorites are untouched.
@MainActor
enum PanelSelfTest {
    static var enabled: Bool { CommandLine.arguments.contains("--self-test-panel") }
    static var steps: Int {
        guard let i = CommandLine.arguments.firstIndex(of: "--self-test-panel"), CommandLine.arguments.indices.contains(i + 1) else { return 400 }
        return Int(CommandLine.arguments[i + 1]) ?? 400
    }
    static let suite = "LunchBarPanelSelfTest"

    static let school: MenuSource = {
        let meals = [MenuType(slug: "lunch", name: "Lunch"), MenuType(slug: "breakfast", name: "Breakfast")]
        return MenuSource(district: "middlesex", school: School(slug: "middlesex-high", name: "Middlesex High", menuTypes: meals), menuType: meals[0])
    }()
    static let hall = RutgersLocations.source(hall: RutgersLocations.foodPro[1]) // Busch, ~140 items

    static func settings() -> AppSettings {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.source = hall
        settings.source = school
        settings.skipWeekends = false
        return settings
    }

    static func log(_ record: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) { print(line); fflush(stdout) }
    }

    private static func fail(_ reason: String, _ record: [String: Any]) -> Never {
        var record = record
        record["result"] = "failed"
        record["reason"] = reason
        log(record)
        cleanUp()
        exit(1)
    }

    private static func cleanUp() {
        for key in ["NSStatusItem Preferred Position", "NSStatusItem Visible", "NSStatusItem VisibleCC"] {
            UserDefaults.standard.removeObject(forKey: key + " LunchBarPanelSelfTest")
        }
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    private static func describe(_ rect: NSRect) -> String { NSStringFromRect(rect) }

    static func run(delegate: AppDelegate) async {
        guard let controller = delegate.panel else { fail("no panel", [:]) }
        let model = delegate.model
        let panel = controller.panel

        // Status item moves while the panel is open: with an auto-hiding menu bar
        // the item's window slides vertically. The panel must not follow.
        var statusMovesWhileOpen: [String] = []
        if let buttonWindow = delegate.statusButtonWindow {
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: buttonWindow, queue: nil) { _ in
                MainActor.assumeIsolated { if controller.isShown { statusMovesWhileOpen.append(describe(buttonWindow.frame)) } }
            }
        }
        // Every frame AppKit reports for the panel, in order.
        var observed: [NSRect] = []
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: nil) { _ in
                MainActor.assumeIsolated { observed.append(panel.frame) }
            }
        }

        func settle() async {
            for _ in 0..<600 {
                if model.phase != .loading && !model.isRefreshing && !model.nutritionLoading { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            // SwiftUI delivers preference changes after its update; give it and any
            // window animation time to finish, then require a stable frame.
            var stable = 0
            var last = panel.frame
            for _ in 0..<200 {
                controller.layoutNow()
                try? await Task.sleep(for: .milliseconds(40))
                if !controller.isSettling && panel.frame == last { stable += 1 } else { stable = 0 }
                last = panel.frame
                if stable >= 4 { return }
            }
        }

        controller.show()
        await settle()
        guard controller.isShown else { fail("panel did not open", [:]) }
        var openTop = panel.frame.maxY
        var openX = panel.frame.minX
        let keyOnOpen = panel.isKeyWindow
        let trackingOptions = (panel.contentView?.subviews ?? []).flatMap(allTrackingOptions)
        log(["event": "open", "frame": describe(panel.frame), "icon": describe(delegate.statusButtonFrame ?? .zero),
             "visible": describe(controller.visibleFrame ?? .zero), "key": keyOnOpen,
             "hoverAreas": trackingOptions.count, "hoverActiveAlways": trackingOptions.filter { $0.contains(.activeAlways) }.count,
             "animates": controller.animates])
        if !keyOnOpen { fail("panel is not key after opening", [:]) }
        if let icon = delegate.statusButtonFrame, let screen = PanelGeometry.screen(for: icon) {
            let anchor = PanelGeometry.anchor(icon: icon, screen: screen.frame, visible: screen.visibleFrame)
            if abs(openTop - anchor.top) > 0.001 || abs(openX - anchor.x) > 0.001 || !screen.visibleFrame.contains(panel.frame) {
                fail("opened away from the status item", ["frame": describe(panel.frame), "icon": describe(icon)])
            }
        }

        // Keyboard and toggling, through the real event path.
        func key(_ code: UInt16, _ characters: String) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: panel.windowNumber, context: nil, characters: characters,
                                                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                    NSApp.sendEvent(event)
                }
            }
        }
        let highlightedOpen = delegate.statusButtonHighlighted
        let dayBefore = model.day
        key(124, String(UnicodeScalar(NSRightArrowFunctionKey)!))
        await settle()
        let arrowMoved = model.day == model.navigator.step(from: dayBefore, by: 1)
        key(123, String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        await settle()
        let arrowBack = model.day == dayBefore
        model.menuFilter = "zz"
        await settle()
        key(53, "\u{1b}")
        await settle()
        let escapeClearedFilter = model.menuFilter.isEmpty && controller.isShown
        key(53, "\u{1b}")
        await settle()
        let escapeClosed = !controller.isShown
        let highlightedClosed = delegate.statusButtonHighlighted
        delegate.togglePanel()
        await settle()
        let toggleShown = controller.isShown
        let toggleKey = panel.isKeyWindow
        // The owner's real case: LunchBar is not the active app when the status
        // item is clicked or the shortcut pressed.
        controller.close()
        NSApp.deactivate()
        await settle()
        let wasActive = NSApp.isActive
        let fallbacksBefore = controller.focusFallbacks
        delegate.togglePanel()
        await settle()
        let inactiveKey = controller.isShown && panel.isKeyWindow
        let usedFallback = controller.focusFallbacks > fallbacksBefore
        let toggleOpened = toggleShown && toggleKey && inactiveKey
        let interaction: [String: Any] = ["event": "interaction", "rightArrowNextDay": arrowMoved, "leftArrowBack": arrowBack,
                                          "escapeClearsFilter": escapeClearedFilter, "escapeCloses": escapeClosed,
                                          "highlightWhileOpen": highlightedOpen, "highlightAfterClose": highlightedClosed,
                                          "toggleReopensKey": toggleOpened, "toggleShown": toggleShown, "toggleKey": toggleKey,
                                          "inactiveBeforeToggle": !wasActive, "inactiveToggleKey": inactiveKey, "inactiveToggleUsedFallback": usedFallback,
                                          "keyWindow": NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none", "active": NSApp.isActive]
        log(interaction)
        if !(arrowMoved && arrowBack && escapeClearedFilter && escapeClosed && highlightedOpen && !highlightedClosed && toggleOpened) {
            fail("interaction check", interaction)
        }
        openTop = panel.frame.maxY
        openX = panel.frame.minX

        var totalResizes = 0
        var maxResizesPerStep = 0
        var maxFrameEventsPerStep = 0
        var totalFrameEvents = 0
        var heights = Set<Int>()
        var kinds: [String: Int] = [:]
        var multiUpdateSteps = 0

        for step in 0..<steps {
            let cycle = step / 12
            let resizesBefore = controller.resizes.count
            let revisionBefore = model.contentRevision
            observed.removeAll()
            var action = ""
            var reopened = false
            switch step % 12 {
            case 0:
                let offsets = [0, 1, -1, 2, 0, -2, 1, 6, 0, -1, 3, -7, 0, 2]
                let offset = offsets[cycle % offsets.count]
                action = "day\(offset >= 0 ? "+" : "")\(offset)"
                model.go(to: model.today.adding(days: offset))
            case 1: action = "next"; model.showNext()
            case 2:
                action = "expand-first"
                if case .menu(let day) = model.phase { model.expandedItemID = day.items.first?.id }
            case 3: action = "collapse"; model.expandedItemID = nil
            case 4:
                action = "toggle-station"
                if case .menu(let day) = model.phase, let section = day.sections.first(where: { $0.title != nil }), let source = model.source {
                    let key = source.key + "/" + (section.providerTitle ?? section.id)
                    let large = day.items.count > 25
                    model.settings.stationExpansion[key] = !(model.settings.stationExpansion[key] ?? !large)
                }
            case 5: action = "filter"; model.menuFilter = ["chi", "a", "sand", "zzz"][cycle % 4]
            case 6: action = "clear-filter"; model.menuFilter = ""
            case 7:
                action = "meal"
                if let source = model.source, let next = source.school.menuTypes.first(where: { $0 != source.menuType && ["Lunch", "Dinner", "lunch", "breakfast"].contains($0.slug) }) {
                    model.select(menuType: next)
                }
            case 8:
                action = "favorite"
                if case .menu(let day) = model.phase, let item = day.items.first { model.settings.toggleFavorite(item) }
            case 9:
                action = "place"
                let next = model.source?.provider == .rutgersFoodPro ? school : hall
                if let saved = model.settings.savedPlaces.first(where: { $0.placeKey == next.placeKey }) { model.select(place: saved) }
                else { model.select(place: next) }
            case 10:
                action = "expand-last"
                if case .menu(let day) = model.phase { model.expandedItemID = (day.items.last { $0.imageURL != nil } ?? day.items.last)?.id }
            default:
                action = "reopen"
                model.expandedItemID = nil
                controller.close()
                await settle()
                controller.show()
                reopened = true
            }
            kinds[action.hasPrefix("day") ? "day" : action, default: 0] += 1
            await settle()

            let frame = panel.frame
            let visible = controller.visibleFrame ?? .zero
            let oracle = PanelMeasure.naturalHeight(model: model)
            let expected = PanelGeometry.height(natural: oracle, top: frame.maxY, visible: visible)
            let stepResizes = Array(controller.resizes.dropFirst(resizesBefore))
            // New content that arrived on its own during the step (a menu download,
            // then FoodPro nutrition seconds later) is a separate update.
            let arrivals = model.contentRevision - revisionBefore
            var record: [String: Any] = [
                "step": step, "action": action, "frame": describe(frame), "visible": describe(visible),
                "natural": controller.naturalHeight, "oracle": oracle, "expected": expected,
                "resizes": stepResizes.count, "frameEvents": observed.count, "arrivals": arrivals,
                "day": model.day.isoString, "place": model.source?.school.name ?? "", "meal": model.source?.menuType.name ?? "",
                "phase": phaseName(model.phase), "expanded": model.expandedItemID != nil, "filter": model.menuFilter,
            ]
            if case .menu(let day) = model.phase { record["items"] = day.items.count }

            if reopened {
                record["key"] = panel.isKeyWindow
                if !panel.isKeyWindow { fail("reopened without key focus", record) }
                // A reopen hangs from wherever the status item is now (an auto-hiding
                // menu bar may have been revealed or hidden in between).
                let icon = delegate.statusButtonFrame ?? .zero
                let screen = PanelGeometry.screen(for: icon)?.frame ?? .zero
                let anchor = PanelGeometry.anchor(icon: icon, screen: screen, visible: visible)
                record["icon"] = describe(icon)
                if abs(frame.maxY - anchor.top) > 0.001 || abs(frame.minX - anchor.x) > 0.001 { fail("reopened away from the status item", record) }
                if stepResizes.count > max(1, arrivals) { fail("more resizes than content updates", record) }
                openTop = frame.maxY; openX = frame.minX
            } else {
                if abs(frame.maxY - openTop) > 0.001 { fail("top edge moved", record) }
                if abs(frame.minX - openX) > 0.001 { fail("horizontal position changed", record) }
                if stepResizes.count > max(1, arrivals) { fail("more resizes than content updates", record) }
                if stepResizes.count > 1 { multiUpdateSteps += 1 }
                if stepResizes.isEmpty && !observed.isEmpty { fail("frame changed without a content change", record) }
                for resize in stepResizes where resize.from == resize.to { fail("no-op resize", record) }
                // Every intermediate animation frame keeps the top and x fixed and moves
                // the height monotonically from the old to the new value (no twitch).
                if stepResizes.count == 1, let resize = stepResizes.first {
                    var previous = resize.from
                    let growing = resize.to > resize.from
                    for f in observed {
                        if abs(f.maxY - openTop) > 0.001 || abs(f.minX - openX) > 0.001 || f.width != PanelGeometry.width {
                            record["badFrame"] = describe(f); fail("intermediate frame left the anchor", record)
                        }
                        if growing ? (f.height < previous - 0.001 || f.height > resize.to + 0.001) : (f.height > previous + 0.001 || f.height < resize.to - 0.001) {
                            record["badFrame"] = describe(f); fail("height reversed during animation", record)
                        }
                        previous = f.height
                    }
                }
            }
            if !controller.isShown { fail("panel closed", record) }
            if frame.width != PanelGeometry.width { fail("width changed", record) }
            if !visible.insetBy(dx: -0.001, dy: -0.001).contains(frame) { fail("panel outside the visible frame", record) }
            if frame.height != PanelGeometry.height(natural: controller.naturalHeight, top: frame.maxY, visible: visible) { fail("height differs from reported natural height", record) }
            if abs(frame.height - expected) > 1 { fail("height differs from independently measured content", record) }
            if frame.height < PanelGeometry.minHeight { fail("collapsed", record) }

            totalResizes += stepResizes.count
            totalFrameEvents += observed.count
            maxResizesPerStep = max(maxResizesPerStep, stepResizes.count)
            maxFrameEventsPerStep = max(maxFrameEventsPerStep, observed.count)
            heights.insert(Int(frame.height))
            log(record)
        }
        log(["result": "passed", "steps": steps, "resizes": totalResizes, "maxResizesPerStep": maxResizesPerStep,
             "frameEvents": totalFrameEvents, "maxFrameEventsPerStep": maxFrameEventsPerStep, "stepsWithTwoContentUpdates": multiUpdateSteps,
             "distinctHeights": heights.sorted(), "actions": kinds, "animates": controller.animates,
             "top": openTop, "x": openX, "focusFallbacks": controller.focusFallbacks,
             "statusItemMovesWhileOpen": statusMovesWhileOpen.count, "statusItemFramesWhileOpen": Array(Set(statusMovesWhileOpen)).sorted()])
        controller.close()
        cleanUp()
        NSApp.terminate(nil)
    }

    private static func phaseName(_ phase: MenuViewModel.Phase) -> String {
        switch phase {
        case .needsSetup: "setup"
        case .loading: "loading"
        case .menu: "menu"
        case .empty: "empty"
        case .failed: "failed"
        }
    }

    private static func allTrackingOptions(_ view: NSView) -> [NSTrackingArea.Options] {
        view.trackingAreas.map(\.options) + view.subviews.flatMap(allTrackingOptions)
    }
}
