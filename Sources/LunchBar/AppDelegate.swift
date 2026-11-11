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

        if settings.source == nil {
            showSettings()
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "LunchBarStatusItem"
        if let button = item.button {
            let image = NSImage(systemSymbolName: "fork.knife", accessibilityDescription: "LunchBar")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("LunchBar")
            button.setAccessibilityHelp("Shows today's school menu")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        let root = PopoverView(
            model: model,
            openSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) }
        )
        let controller = NSHostingController(rootView: root)
        // Let the popover follow the SwiftUI content's size, so short menus get a short popover.
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        model.popoverWillOpen()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
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
        guard let source = settings.source else { return }
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
