import AppKit
import SwiftUI

/// Geometry rules for the menu window, kept free of AppKit state so the
/// controller, the self-test and the snapshot renderer agree on them.
enum PanelGeometry {
    static let width: CGFloat = 360
    static let maxHeight: CGFloat = 460
    static let minHeight: CGFloat = 120
    static let cornerRadius: CGFloat = 14
    /// Space between the bottom of the menu bar and the top of the window.
    static let gapBelowMenuBar: CGFloat = 5
    /// Closest the window may come to the left or right edge of the screen.
    static let screenMargin: CGFloat = 6

    /// The window height for a natural content height, given the top edge and the
    /// visible frame of the screen it hangs on.
    static func height(natural: CGFloat, top: CGFloat, visible: NSRect) -> CGFloat {
        let available = max(minHeight, top - visible.minY - screenMargin)
        return min(max(ceil(natural), minHeight), min(maxHeight, available))
    }

    /// Top edge and horizontal origin for a window under the status item `icon`
    /// (screen coordinates) on `screen`.
    ///
    /// The vertical position comes from the screen, never from the status item's
    /// own y: with an auto-hiding menu bar the item's window sits above the screen
    /// while hidden and slides in when revealed. The window always hangs just
    /// below where the menu bar is (or appears), so it neither moves with the bar
    /// nor ends up under it.
    static func anchor(icon: NSRect, screen: NSRect, visible: NSRect) -> (top: CGFloat, x: CGFloat) {
        let barBottom: CGFloat
        if visible.maxY < screen.maxY - 0.5 {
            barBottom = visible.maxY
        } else {
            // Menu bar hidden: it is as tall as the status item's window when it appears.
            let barHeight = icon.height > 0 ? icon.height : max(NSStatusBar.system.thickness, 24)
            barBottom = screen.maxY - barHeight
        }
        let top = barBottom - gapBelowMenuBar
        let lowest = visible.minX + screenMargin
        let highest = max(lowest, visible.maxX - width - screenMargin)
        let x = min(max((icon.midX - width / 2).rounded(), lowest), highest)
        return (top, x)
    }

    /// The screen whose menu bar holds the status item. `NSStatusBarWindow.screen`
    /// can be nil, and a hidden item's window can sit just above its screen, so
    /// match on x and take the screen whose top edge is nearest the item.
    static func screen(for icon: NSRect) -> NSScreen? {
        let screens = NSScreen.screens
        return screenIndex(for: icon, frames: screens.map(\.frame)).map { screens[$0] } ?? NSScreen.main
    }

    static func screenIndex(for icon: NSRect, frames: [NSRect]) -> Int? {
        let columns = frames.indices.filter { icon.midX >= frames[$0].minX && icon.midX < frames[$0].maxX }
        return columns.min { abs(frames[$0].maxY - icon.midY) < abs(frames[$1].maxY - icon.midY) }
    }
}

/// A borderless panel that can take keyboard focus without activating the app,
/// like a popover does.
final class MenuPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: PanelGeometry.width, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        becomesKeyOnlyIfNeeded = false
        setAccessibilitySubrole(.floatingWindow)
        setAccessibilityLabel("LunchBar")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Rounded, vibrant background with a hairline border. The mask image gives the
/// window its shape, so the system shadow follows the rounded corners.
final class PanelBackgroundView: NSVisualEffectView {
    private let border = BorderView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        maskImage = Self.mask(radius: PanelGeometry.cornerRadius)
        border.frame = bounds
        border.autoresizingMask = [.width, .height]
        addSubview(border)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func install(_ content: NSView) {
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content, positioned: .below, relativeTo: border)
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private final class BorderView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var isOpaque: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let color: NSColor = dark
                ? .white.withAlphaComponent(contrast ? 0.45 : 0.16)
                : .black.withAlphaComponent(contrast ? 0.55 : 0.12)
            color.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: PanelGeometry.cornerRadius - 0.5, yRadius: PanelGeometry.cornerRadius - 0.5)
            path.lineWidth = 1
            path.stroke()
        }

        override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    }
}

/// Shows the menu window under the status item and keeps its size equal to the
/// content's natural height. The window is positioned by this controller alone:
/// its top edge and horizontal position are fixed while it is open, and only the
/// bottom edge moves when the content changes height.
@MainActor
final class MenuPanelController: NSObject, NSWindowDelegate {
    struct Resize { let from: CGFloat; let to: CGFloat; let natural: CGFloat }

    let panel = MenuPanel()
    private let hosting: NSHostingView<AnyView>
    private weak var statusButton: NSStatusBarButton?
    private let model: MenuViewModel
    /// Natural content height last reported by SwiftUI (header + list + footer).
    private(set) var naturalHeight: CGFloat = 0
    private var pendingNatural: CGFloat?
    private var updateQueued = false
    /// Height the window is at, or animating to.
    private(set) var targetHeight: CGFloat = 0
    private(set) var isAnimating = false
    private var animationGeneration = 0
    private var top: CGFloat = 0
    private var originX: CGFloat = 0
    private var observers: [NSObjectProtocol] = []
    private var eventMonitors: [Any] = []
    private var lastDismissal = Date.distantPast
    /// Resizes this controller performed, for the self-test.
    private(set) var resizes: [Resize] = []
    /// Times the panel opened without key focus and the app had to activate.
    private(set) var focusFallbacks = 0
    /// The app that was in front when the panel opened, and whether opening the
    /// panel activated LunchBar. Closing hands activation back to it.
    private var previousApp: NSRunningApplication?
    private var activatedForPanel = false
    var animates = true
    var dismissesOnFocusLoss = true
    var onClose: (() -> Void)?

    var isShown: Bool { panel.isVisible }

    init(model: MenuViewModel, statusButton: NSStatusBarButton?, rootView: (_ onNaturalHeight: @escaping (CGFloat) -> Void) -> AnyView) {
        self.model = model
        self.statusButton = statusButton
        var report: (CGFloat) -> Void = { _ in }
        hosting = NSHostingView(rootView: rootView { report($0) })
        super.init()
        report = { [weak self] height in self?.contentHeightChanged(height) }
        // The window owns its size. The hosting view must never push min/max/ideal
        // sizes back into the window, or the two would negotiate (the old feedback loop).
        hosting.sizingOptions = []
        let background = PanelBackgroundView(frame: NSRect(x: 0, y: 0, width: PanelGeometry.width, height: 300))
        background.install(hosting)
        panel.contentView = background
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.handleEscape() }
    }

    // MARK: Showing and hiding

    func toggle() {
        if isShown { close() }
        // A click on the status item that also dismissed the panel (focus loss)
        // must not immediately reopen it.
        else if Date().timeIntervalSince(lastDismissal) > 0.3 { show() }
    }

    func show() {
        guard !isShown, let geometry = currentAnchor() else { return }
        model.panelWillOpen()
        top = geometry.top
        originX = geometry.x
        let natural = pendingNatural ?? naturalHeight
        pendingNatural = nil
        naturalHeight = natural
        targetHeight = PanelGeometry.height(natural: natural > 0 ? natural : PanelGeometry.maxHeight, top: geometry.top, visible: geometry.visible)
        resizes.removeAll()
        panel.setFrame(frame(height: targetHeight), display: false)
        // Lay out once at that size; if SwiftUI reports a height during layout,
        // open at that height instead of resizing right after appearing.
        hosting.layoutSubtreeIfNeeded()
        if let reported = pendingNatural {
            pendingNatural = nil
            naturalHeight = reported
            targetHeight = PanelGeometry.height(natural: reported, top: geometry.top, visible: geometry.visible)
            panel.setFrame(frame(height: targetHeight), display: false)
        }
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        activatedForPanel = false
        if !panel.isKeyWindow {
            // An inactive accessory app cannot always give its panel key focus.
            // Ask to activate (as the old popover always did); activation arrives
            // asynchronously, and the didBecomeActive observer makes the panel key.
            focusFallbacks += 1
            // The plain `activate()` is a cooperative request that macOS may refuse
            // for an accessory app; this form still takes focus as popovers did.
            NSApp.activate(ignoringOtherApps: true)
            activatedForPanel = true
        }
        // Keep the filter field from grabbing focus on open: arrow keys and T
        // should navigate days until the person clicks or tabs into a control.
        panel.makeFirstResponder(nil)
        statusButton?.highlight(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown else { return }
            self.statusButton?.highlight(true)
        }
        NSAccessibility.post(element: panel, notification: .focusedWindowChanged)
        startObserving()
        // Content may have reported a new height during the first layout.
        scheduleUpdate()
    }

    func close() {
        guard isShown else { return }
        stopObserving()
        animationGeneration += 1
        isAnimating = false
        panel.orderOut(nil)
        statusButton?.highlight(false)
        // Only if opening the panel activated LunchBar, and only while LunchBar is
        // still the active app (a click elsewhere already moved focus on its own).
        if activatedForPanel, NSApp.isActive, let previousApp, !previousApp.isTerminated,
           !NSApp.windows.contains(where: { $0 !== panel && $0.isVisible && $0.canBecomeMain }) {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        activatedForPanel = false
        previousApp = nil
        onClose?()
    }

    private func dismiss() {
        guard isShown else { return }
        lastDismissal = Date()
        close()
    }

    private func handleEscape() {
        if !model.menuFilter.isEmpty { model.menuFilter = "" } else { close() }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard dismissesOnFocusLoss else { return }
        // A SwiftUI Menu opened from the panel takes key focus while it tracks;
        // it is attached to the panel, so do not treat it as leaving.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown, !self.panel.isKeyWindow, NSApp.keyWindow?.parent !== self.panel else { return }
            self.dismiss()
        }
    }

    private func startObserving() {
        stopObserving()
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { if self?.dismissesOnFocusLoss == true { self?.dismiss() } }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShown, !self.panel.isKeyWindow else { return }
                self.panel.makeKey()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.dismissesOnFocusLoss == true { self?.dismiss() } }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reanchor(screensChanged: true) }
        })
        if let buttonWindow = statusButton?.window {
            observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: buttonWindow, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reanchor(screensChanged: false) }
            })
        }
        if dismissesOnFocusLoss, let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.window === self.panel, event.keyCode == 53 else { return event }
            self.handleEscape()
            return nil
        }) {
            eventMonitors.append(monitor)
        }
    }

    private func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    // MARK: Geometry

    private func currentAnchor() -> (top: CGFloat, x: CGFloat, visible: NSRect)? {
        guard let icon = statusButton?.window?.frame, let screen = PanelGeometry.screen(for: icon) else { return nil }
        let anchor = PanelGeometry.anchor(icon: icon, screen: screen.frame, visible: screen.visibleFrame)
        return (anchor.top, anchor.x, screen.visibleFrame)
    }

    var visibleFrame: NSRect? {
        guard let icon = statusButton?.window?.frame else { return nil }
        return PanelGeometry.screen(for: icon)?.visibleFrame
    }

    /// The fixed top edge and left edge chosen when the panel opened.
    var anchoredTop: CGFloat { top }
    var anchoredX: CGFloat { originX }

    private func frame(height: CGFloat) -> NSRect {
        NSRect(x: originX, y: top - height, width: PanelGeometry.width, height: height)
    }

    /// The status item moved sideways (another item appeared) or the displays
    /// changed: hang the panel from the new position in one step. Vertical moves
    /// of the status item alone (an auto-hiding menu bar sliding away) keep the
    /// panel where it is.
    private func reanchor(screensChanged: Bool) {
        guard isShown, let geometry = currentAnchor() else { return }
        let newTop = screensChanged ? geometry.top : top
        let height = PanelGeometry.height(natural: naturalHeight, top: newTop, visible: geometry.visible)
        guard newTop != top || geometry.x != originX || height != targetHeight else { return }
        animationGeneration += 1
        isAnimating = false
        top = newTop
        originX = geometry.x
        targetHeight = height
        panel.setFrame(frame(height: height), display: true)
    }

    // MARK: Content height

    private func contentHeightChanged(_ height: CGFloat) {
        guard height > 0 else { return }
        pendingNatural = height
        scheduleUpdate()
    }

    /// Any number of SwiftUI preference changes in one run-loop turn become one resize.
    private func scheduleUpdate() {
        guard !updateQueued else { return }
        updateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateQueued = false
            self.applyPendingHeight()
        }
    }

    private func applyPendingHeight() {
        if let pending = pendingNatural {
            naturalHeight = pending
            pendingNatural = nil
        }
        guard isShown, let visible = visibleFrame, naturalHeight > 0 else { return }
        let height = PanelGeometry.height(natural: naturalHeight, top: top, visible: visible)
        // Only a change in the content's own height moves the window. Window
        // resizes never change the reported height (it is measured unconstrained).
        guard height != targetHeight else { return }
        resizes.append(Resize(from: targetHeight, to: height, natural: naturalHeight))
        targetHeight = height
        let target = frame(height: height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animates, !reduceMotion else {
            animationGeneration += 1
            isAnimating = false
            panel.setFrame(target, display: true)
            return
        }
        animationGeneration += 1
        let generation = animationGeneration
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.animationGeneration else { return }
                self.isAnimating = false
                // Land exactly on the target in case the animation was cut short.
                if self.panel.frame != target, self.isShown { self.panel.setFrame(target, display: true) }
            }
        }
    }

    /// True while a height update is queued or animating.
    var isSettling: Bool { updateQueued || isAnimating || pendingNatural != nil }

    func layoutNow() {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
    }
}
