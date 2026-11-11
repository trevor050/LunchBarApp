import AppKit
import LunchKit
import SwiftUI

/// Owns the status item, popover, settings window, global hotkey and the
/// shared models. Plain AppKit on purpose: `MenuBarExtra` can't be opened
/// programmatically, which a global shortcut needs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let settings: AppSettings
    let repository: MenuRepository
    let model: MenuViewModel
    let finder: SchoolFinder
    let loginItem = LoginItem()
    let hotKeyStatus = HotKeyStatus()
    lazy var notifier = FavoriteNotifier(settings: settings)

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let popoverAnchor = StatusPopoverAnchor()
    private var popoverTransitioning = false
    private var pendingPopoverSize: CGSize?
    private var popoverUpdateQueued = false
    private var correctingAnchor = false
    private var observedPopoverWindow: NSWindow?
    private var popoverWindowObservers: [NSObjectProtocol] = []
    private let hotKey = GlobalHotKey()
    private var settingsWindow: NSWindow?

    init(settings: AppSettings = AppSettings(), now: @escaping () -> Date = Date.init) {
        self.settings = settings
        let client = NutrisliceClient()
        repository = MenuRepository(client: client, cache: MenuCache(directory: MenuCache.defaultDirectory()))
        model = MenuViewModel(settings: settings, repository: repository, now: now)
        finder = SchoolFinder(client: client)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if settings.source == nil, let imported = LegacyConfig.importSource() {
            settings.source = imported
        }

        setUpStatusItem()
        setUpPopover()
        registerHotKey()
        NotificationCenter.default.addObserver(forName: .lunchBarSuspendHotKey, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotKey.unregister() }
        }

        model.onWeekLoaded = { [weak self] source, week in
            self?.notifier.update(source: source, week: week)
        }
        notifier.startDailyChecks { [weak self] in self?.checkFavorites() }

        Task { await repository.cache.prune(olderThan: LocalDate(Date()).adding(days: -60)) }

        if PopoverSelfTest.enabled { Task { await PopoverSelfTest.run(delegate: self) } }

        if settings.source == nil {
            showSettings()
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let name = PopoverSelfTest.enabled ? "LunchBarPopoverSelfTest" : "LunchBarStatusItem"
        if PopoverSelfTest.enabled && CommandLine.arguments.contains("--right-edge") {
            // A separate autosave identity leaves the owner's icon preference alone.
            UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position " + name)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = name
        if let button = item.button {
            let image = NSImage(systemSymbolName: "fork.knife", accessibilityDescription: "LunchBar")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("LunchBar")
            button.setAccessibilityHelp("Shows today's school menu")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // A permanent, non-interactive view keeps positioning independent of
            // NSStatusBarButton's highlighting and special window layout.
            popoverAnchor.frame = button.bounds
            popoverAnchor.autoresizingMask = [.width, .height]
            button.addSubview(popoverAnchor)
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Menu", action: #selector(refreshMenu), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LunchBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // restore click-to-open-popover behavior
    }

    @objc private func refreshMenu() { model.refresh() }
    @objc private func openSettingsFromMenu() { showSettings() }

    // MARK: Popover

    private func setUpPopover() {
        popover.behavior = PopoverSelfTest.enabled ? .applicationDefined : .transient
        popover.animates = !PopoverSelfTest.enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.hasFullSizeContent = false
        let root = PopoverView(
            model: model,
            openSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) },
            onSizeChange: { [weak self] size in self?.requestPopoverUpdate(size: size) },
            onNavigation: { [weak self] in self?.requestPopoverUpdate() }
        )
        // A plain controller cannot forward SwiftUI preferredContentSize updates
        // to AppKit. The hosting view still lays out and reports natural geometry.
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.frame = CGRect(origin: .zero, size: PopoverView.size)
        let controller = NSViewController()
        controller.view = hosting
        popover.contentViewController = controller
        popover.contentSize = PopoverView.size
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard statusItem?.button?.window != nil else { return }
        statusItem?.button?.layoutSubtreeIfNeeded()
        popoverAnchor.frame = statusItem?.button?.bounds ?? popoverAnchor.frame
        model.popoverWillOpen()
        if let size = pendingPopoverSize { popover.contentSize = size; pendingPopoverSize = nil }
        popoverTransitioning = true
        if PopoverSelfTest.enabled { PopoverSelfTest.log(["event": "show", "anchor": NSStringFromRect(popoverAnchor.bounds), "visible": NSStringFromRect(popoverAnchor.visibleRect), "button": NSStringFromRect(statusItem?.button?.bounds ?? .zero)]) }
        popover.show(relativeTo: popoverAnchor.bounds, of: popoverAnchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }

    func popoverDidShow(_ notification: Notification) {
        popoverTransitioning = false
        if PopoverSelfTest.enabled { PopoverSelfTest.log(["event": "didShow"]) }
        observePopoverWindow()
        requestPopoverUpdate()
    }

    func popoverWillClose(_ notification: Notification) { popoverTransitioning = true }

    func popoverDidClose(_ notification: Notification) {
        popoverTransitioning = false
        statusItem?.button?.highlight(false)
    }

    /// One main-run-loop update for any number of SwiftUI preference changes.
    private func requestPopoverUpdate(size: CGSize? = nil) {
        if let size, size.width > 0, size.height > 0 {
            pendingPopoverSize = CGSize(width: PopoverView.size.width, height: ceil(size.height))
        }
        guard !popoverUpdateQueued else { return }
        popoverUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.popoverUpdateQueued = false
            self.applyPopoverUpdate()
        }
    }

    private func applyPopoverUpdate() {
        guard popover.isShown, !popoverTransitioning else { return }
        let animates = popover.animates
        popover.animates = false
        defer { popover.animates = animates }
        if let size = pendingPopoverSize {
            pendingPopoverSize = nil
            if popover.contentSize != size {
                popover.contentSize = size
                popover.positioningRect = popoverAnchor.bounds
            }
        }
        enforcePopoverAnchor()
    }

    private func observePopoverWindow() {
        guard let window = popover.contentViewController?.view.window, observedPopoverWindow !== window else { return }
        popoverWindowObservers.forEach(NotificationCenter.default.removeObserver)
        observedPopoverWindow = window
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            popoverWindowObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enforcePopoverAnchor() }
            })
        }
        popoverWindowObservers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: statusItem?.button?.window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestPopoverUpdate() }
        })
    }

    private var statusItemScreen: NSScreen? {
        guard let frame = statusItem?.button?.window?.frame else { return nil }
        // NSStatusBarWindow.screen can be nil. Match its global coordinates.
        return NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main
    }

    private func enforcePopoverAnchor() {
        guard popover.isShown, !popoverTransitioning, !correctingAnchor,
              let icon = statusItem?.button?.window?.frame,
              let screen = statusItemScreen,
              let window = popover.contentViewController?.view.window,
              !Self.isAnchored(window.frame, below: icon, visible: screen.visibleFrame) else { return }
        correctingAnchor = true
        defer { correctingAnchor = false }
        anchorGuardFires += 1
        let before = window.frame
        var frame = before
        let visible = screen.visibleFrame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(icon.midX - frame.width / 2, visible.minX), visible.maxX - frame.width)
        // Pin the TOP, then derive the bottom from the final window height.
        // Status-item windows include private margins: the visible frame is the
        // hard ceiling, rather than an assumed four-point arrow overlap.
        frame.origin.y = min(visible.maxY, icon.minY) - frame.height
        frame.origin.y = max(frame.origin.y, visible.minY)
        window.setFrame(frame, display: true, animate: false)
        NSLog("LunchBar anchor guard corrected %@ -> %@, icon %@, visible %@", NSStringFromRect(before), NSStringFromRect(frame), NSStringFromRect(icon), NSStringFromRect(visible))
        if PopoverSelfTest.enabled { PopoverSelfTest.log(["guard": true, "before": NSStringFromRect(before), "after": NSStringFromRect(frame), "visible": NSStringFromRect(visible)]) }
    }

    private static func isAnchored(_ frame: NSRect, below icon: NSRect, visible: NSRect) -> Bool {
        let targetTop = min(visible.maxY, icon.minY)
        return visible.insetBy(dx: -0.5, dy: -0.5).contains(frame)
            && frame.maxY <= visible.maxY + 0.5
            && abs(frame.maxY - targetTop) <= 0.5
            && frame.minX <= icon.midX && frame.maxX >= icon.midX
    }

    func settlePopoverLayout() {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    private(set) var anchorGuardFires = 0

    func anchorDiagnostic(step: Int) -> [String: Any] {
        guard let icon = statusItem?.button?.window?.frame,
              let frame = popover.contentViewController?.view.window?.frame else {
            return ["step": step, "valid": false, "reason": "missing window"]
        }
        // AppKit includes the arrow and shadow margins in the window frame.
        let screen = statusItemScreen
        let visible = screen?.visibleFrame ?? .zero
        let content = popover.contentViewController!.view
        let contentFrame = content.window!.convertToScreen(content.convert(content.bounds, to: nil))
        // AppKit exposes preferredEdge but no getter for the rendered arrow edge.
        // Verify that the anchor is geometrically above the complete window and
        // the content is inset below its top, with full-size arrow content disabled.
        let arrowAtTop = icon.midY >= frame.maxY && contentFrame.maxY < frame.maxY && !popover.hasFullSizeContent
        let valid = popover.isShown && arrowAtTop && Self.isAnchored(frame, below: icon, visible: visible)
        return ["step": step, "valid": valid, "popover": NSStringFromRect(frame), "icon": NSStringFromRect(icon),
                "visible": NSStringFromRect(visible), "screen": NSStringFromRect(screen?.frame ?? .zero),
                "content": NSStringFromRect(contentFrame), "topInset": frame.maxY - contentFrame.maxY, "bottomInset": contentFrame.minY - frame.minY,
                "anchorEdge": arrowAtTop ? "top" : "invalid", "shown": popover.isShown, "transition": popoverTransitioning, "anchor": NSStringFromRect(popoverAnchor.bounds), "height": popover.contentSize.height, "guardFires": anchorGuardFires,
                "day": model.day.isoString, "meal": settings.source?.menuType.slug ?? "",
                "expanded": model.expandedItemID != nil, "favorites": settings.favorites.count]
    }

    // MARK: Hotkey

    func registerHotKey() {
        hotKey.unregister()
        hotKeyStatus.conflict = false
        guard let combo = settings.hotKey else { return }
        let ok = hotKey.register(combo) { [weak self] in self?.togglePopover() }
        hotKeyStatus.conflict = !ok
    }

    // MARK: Settings window

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings,
                finder: finder,
                loginItem: loginItem,
                hotKeyStatus: hotKeyStatus,
                onSourceChange: { [weak self] in self?.sourceDidChange() },
                onHotKeyChange: { [weak self] in self?.registerHotKey() },
                onNotificationsChange: { [weak self] in self?.checkFavorites() },
                requestNotifications: { [weak self] in await self?.notifier.requestAuthorization() ?? false }
            )
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.title = "LunchBar Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("LunchBarSettings")
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func sourceDidChange() {
        model.sourceDidChange()
        checkFavorites()
    }

    // MARK: Favorites

    private func checkFavorites() {
        guard let source = settings.source, source.provider != .rutgersFoodPro else { return }
        guard settings.notifyFavorites, !settings.favorites.isEmpty else {
            notifier.removeAll()
            return
        }
        let today = LocalDate(Date())
        Task {
            // This week, plus next week from Thursday on so Monday's favorites get scheduled.
            var days = [today]
            if today.weekday >= 5 { days.append(today.adding(days: 7)) }
            for day in days {
                if let result = try? await repository.week(source: source, containing: day) {
                    notifier.update(source: source, week: result.week)
                }
            }
        }
    }
}

/// Invisible without being hidden (hidden views cannot position a popover).
private final class StatusPopoverAnchor: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
