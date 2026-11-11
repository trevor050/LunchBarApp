import AppKit
import LunchKit
import Observation
import ServiceManagement
import UserNotifications

/// True when running from an assembled `.app` (not `swift run`). Login items and
/// notifications need a real bundle identity.
var isRunningFromAppBundle: Bool {
    Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
}

/// Wraps `SMAppService.mainApp` (macOS 13+), the supported way to launch at login.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    init() { refresh() }

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = isRunningFromAppBundle ? SMAppService.mainApp.status : .notFound
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Schedules a local notification on mornings when a favorite item is on the menu.
///
/// No background polling: it piggybacks on weeks the app already loads, plus one
/// check per day (at launch, on wake, and at 6 AM) that usually hits the cache.
@MainActor
final class FavoriteNotifier {
    private let settings: AppSettings
    private var dailyTimer: Timer?
    private static let identifierPrefix = "favorite-"
    static let notifyHour = 7
    static let notifyMinute = 30

    init(settings: AppSettings) {
        self.settings = settings
    }

    private var center: UNUserNotificationCenter? {
        isRunningFromAppBundle ? .current() : nil
    }

    /// Asks for permission. Returns whether alerts are allowed.
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationDenied() async -> Bool {
        guard let center else { return true }
        return await center.notificationSettings().authorizationStatus == .denied
    }

    /// Reconciles pending notifications for one loaded week.
    func update(source: MenuSource, week: MenuWeek, now: Date = Date()) {
        guard let center else { return }
        let today = LocalDate(now)
        let favorites = settings.favoriteKeys
        let enabled = settings.notifyFavorites && settings.source == source
        let prefix = "\(Self.identifierPrefix)\(source.key)-"

        var toAdd: [UNNotificationRequest] = []
        var toRemove: [String] = []
        for day in week.days where day.date >= today {
            let id = prefix + day.date.isoString
            let matches = enabled ? Favorites.matches(in: day, favorites: favorites) : []
            guard !matches.isEmpty else {
                toRemove.append(id)
                continue
            }
            let components = DateComponents(
                year: day.date.year, month: day.date.month, day: day.date.day,
                hour: Self.notifyHour, minute: Self.notifyMinute
            )
            guard let fireDate = Calendar.current.date(from: components), fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            let names = matches.map(\.name)
            content.title = names.count == 1 ? "\(names[0]) is on the menu today" : "Favorites on the menu today"
            content.body = names.count == 1
                ? "\(source.school.name) · \(source.menuType.name)"
                : names.joined(separator: ", ")
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            toAdd.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        center.removePendingNotificationRequests(withIdentifiers: toRemove)
        for request in toAdd {
            center.add(request) { _ in }
        }
    }

    func removeAll() {
        guard let center else { return }
        Task {
            let pending = await center.pendingNotificationRequests()
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Fires `check` at launch, after wake, and every morning at 6.
    func startDailyChecks(_ check: @escaping @MainActor () -> Void) {
        check()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { check() }
        }
        scheduleNextMorning(check)
    }

    private func scheduleNextMorning(_ check: @escaping @MainActor () -> Void) {
        dailyTimer?.invalidate()
        let calendar = Calendar.current
        guard let next = calendar.nextDate(after: Date(), matching: DateComponents(hour: 6, minute: 0), matchingPolicy: .nextTime) else {
            return
        }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                check()
                self?.scheduleNextMorning(check)
            }
        }
        timer.tolerance = 15 * 60
        RunLoop.main.add(timer, forMode: .common)
        dailyTimer = timer
    }
}
