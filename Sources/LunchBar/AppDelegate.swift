import AppKit
import LunchKit
import SwiftUI

/// Owns the status item, menu window, settings window, global hotkey and the
/// shared models. Plain AppKit on purpose: `MenuBarExtra` can't be opened
/// programmatically, which a global shortcut needs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let repository: MenuRepository
    let model: MenuViewModel
    let finder: SchoolFinder
    let loginItem = LoginItem()
    let hotKeyStatus = HotKeyStatus()
    lazy var notifier = FavoriteNotifier(settings: settings)

    private var statusItem: NSStatusItem?
    private(set) var panel: MenuPanelController?
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
        setUpPanel()
        registerHotKey()
        NotificationCenter.default.addObserver(forName: .lunchBarSuspendHotKey, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotKey.unregister() }
        }

        model.onWeekLoaded = { [weak self] source, week in
            self?.notifier.update(source: source, week: week)
        }
        notifier.startDailyChecks { [weak self] in self?.checkFavorites() }

        Task { await repository.cache.prune(olderThan: LocalDate(Date()).adding(days: -60)) }

        if PanelSelfTest.enabled { Task { await PanelSelfTest.run(delegate: self) } }

        if settings.source == nil {
            showSettings()
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let name = PanelSelfTest.enabled ? "LunchBarPanelSelfTest" : "LunchBarStatusItem"
        if PanelSelfTest.enabled && CommandLine.arguments.contains("--right-edge") {
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
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        panel?.close()
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Menu", action: #selector(refreshMenu), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit LunchBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // restore click-to-open behavior
    }

    @objc private func refreshMenu() { model.refresh() }
    @objc private func openSettingsFromMenu() { showSettings() }

    // MARK: Menu window

    private func setUpPanel() {
        let controller = MenuPanelController(model: model, statusButton: statusItem?.button) { [weak self] report in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PanelView(
                model: self.model,
                openSettings: { [weak self] in self?.showSettings() },
                quit: { NSApp.terminate(nil) },
                onNaturalHeight: report
            ))
        }
        if PanelSelfTest.enabled {
            controller.dismissesOnFocusLoss = false
            controller.animates = !CommandLine.arguments.contains("--no-animation")
        }
        panel = controller
    }

    func togglePanel() { panel?.toggle() }
    var statusButtonFrame: NSRect? { statusItem?.button?.window?.frame }
    var statusButtonHighlighted: Bool { statusItem?.button?.isHighlighted ?? false }
    func showPanel() { panel?.show() }

    // MARK: Hotkey

    func registerHotKey() {
        hotKey.unregister()
        hotKeyStatus.conflict = false
        guard let combo = settings.hotKey else { return }
        let ok = hotKey.register(combo) { [weak self] in self?.togglePanel() }
        hotKeyStatus.conflict = !ok
    }

    // MARK: Settings window

    func showSettings() {
        panel?.close()
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
