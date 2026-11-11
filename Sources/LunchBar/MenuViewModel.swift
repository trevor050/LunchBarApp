import Foundation
import LunchKit
import Observation

/// Drives the popover: which day is shown, and what state that day is in.
@MainActor
@Observable
final class MenuViewModel {
    enum Phase: Equatable {
        case needsSetup
        case loading
        case menu(MenuDay)
        case empty(EmptyReason)
        case failed(NutrisliceError)
    }

    enum EmptyReason: Equatable {
        case holiday(String)
        case weekend
        case notPosted(notes: [String])
    }

    private(set) var phase: Phase = .loading
    private(set) var day: LocalDate
    private(set) var today: LocalDate
    /// Set when showing a saved copy because the refresh failed.
    private(set) var staleNotice: String?
    private(set) var isRefreshing = false
    private(set) var week: MenuWeek?

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let repository: MenuRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var lastOpenedToday: LocalDate?
    @ObservationIgnored var onWeekLoaded: ((MenuSource, MenuWeek) -> Void)?

    init(settings: AppSettings, repository: MenuRepository, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.repository = repository
        self.now = now
        let today = LocalDate(now())
        self.today = today
        self.day = DayNavigator(skipWeekends: settings.skipWeekends).initialDay(today: today)
    }

    var navigator: DayNavigator { DayNavigator(skipWeekends: settings.skipWeekends) }
    var source: MenuSource? { settings.source }
    var isShowingDefaultDay: Bool { day == navigator.initialDay(today: today) }

    /// The next day in the loaded week that has food, for the "Next menu" button.
    var nextMenuDay: LocalDate? {
        week?.days.first { $0.date > day && $0.hasFood }?.date
    }

    // MARK: Actions

    /// Called every time the popover opens. Jumps back to today after midnight or
    /// after a long sleep, then refreshes if the cached copy is old.
    func popoverWillOpen() {
        today = LocalDate(now())
        if lastOpenedToday != today {
            lastOpenedToday = today
            day = navigator.initialDay(today: today)
        }
        load()
    }

    func showNext() { move(by: 1) }
    func showPrevious() { move(by: -1) }

    func showToday() {
        today = LocalDate(now())
        go(to: navigator.initialDay(today: today))
    }

    func go(to date: LocalDate) {
        guard date != day else { return }
        day = date
        load()
    }

    func refresh() { load(force: true) }

    func select(menuType: MenuType) {
        guard var source = settings.source, source.menuType != menuType else { return }
        source.menuType = menuType
        settings.source = source
        sourceDidChange()
    }

    func sourceDidChange() {
        week = nil
        staleNotice = nil
        load()
    }

    private func move(by count: Int) {
        go(to: navigator.step(from: day, by: count))
    }

    // MARK: Loading

    func load(force: Bool = false) {
        loadGeneration += 1
        let generation = loadGeneration
        guard let source = settings.source else {
            phase = .needsSetup
            return
        }
        let day = day

        // Paint instantly from the week already in memory when we can.
        if let week, week.start == day.weekStart {
            apply(week, source: source)
        }

        Task {
            var painted = self.week?.start == day.weekStart
            if !painted, let cached = await repository.cachedWeek(source: source, containing: day) {
                guard generation == loadGeneration else { return }
                self.week = cached.week
                apply(cached.week, source: source)
                painted = true
            }
            guard generation == loadGeneration else { return }
            if !painted { phase = .loading }

            isRefreshing = true
            defer { if generation == loadGeneration { isRefreshing = false } }
            do throws(NutrisliceError) {
                let result = try await repository.week(source: source, containing: day, forceRefresh: force)
                guard generation == loadGeneration else { return }
                self.week = result.week
                staleNotice = result.refreshError.map { Self.staleMessage(for: $0, savedAt: result.fetchedAt) }
                apply(result.week, source: source)
                onWeekLoaded?(source, result.week)
            } catch {
                guard generation == loadGeneration else { return }
                staleNotice = nil
                if !painted { phase = .failed(error) } else { staleNotice = Self.staleMessage(for: error, savedAt: nil) }
            }
        }
    }

    private func apply(_ week: MenuWeek, source: MenuSource) {
        let menuDay = week.day(day)
        if let menuDay, menuDay.hasFood {
            phase = .menu(menuDay)
        } else if let holiday = menuDay?.holiday {
            phase = .empty(.holiday(holiday))
        } else if day.isWeekend {
            phase = .empty(.weekend)
        } else {
            phase = .empty(.notPosted(notes: menuDay?.notes ?? []))
        }
    }

    static func staleMessage(for error: NutrisliceError, savedAt: Date?) -> String {
        let saved = savedAt.map { "saved \($0.formatted(.relative(presentation: .named)))" } ?? "saved earlier"
        switch error {
        case .offline: return "Offline · showing the menu \(saved)"
        default: return "Couldn't refresh · showing the menu \(saved)"
        }
    }
}
