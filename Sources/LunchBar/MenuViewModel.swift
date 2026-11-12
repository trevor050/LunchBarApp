import Foundation
import LunchKit
import Observation

/// Drives the menu window: which day is shown, and what state that day is in.
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

    private(set) var phase: Phase = .loading {
        didSet { if phase != .loading { contentRevision += 1 } }
    }
    /// Counts arrivals of new content (not entries into loading), for the self-test.
    @ObservationIgnored private(set) var contentRevision = 0
    /// Height of the last content shown, so a loading state can keep the window's
    /// size instead of shrinking to a spinner and growing back.
    @ObservationIgnored var lastContentHeight: CGFloat = 0
    private(set) var day: LocalDate
    private(set) var today: LocalDate
    /// Set when showing a saved copy because the refresh failed.
    private(set) var staleNotice: String?
    private(set) var isRefreshing = false
    private(set) var nutritionLoading = false
    private(set) var nutritionNotice: String?
    private(set) var verifiedRecipes: Set<String> = []
    @ObservationIgnored private var nutritionTask: Task<Void, Never>?
    private(set) var week: MenuWeek?
    /// The item whose details are expanded in the list.
    var expandedItemID: String?
    var menuFilter = ""

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let repository: MenuRepository
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var nutritionGeneration = 0
    @ObservationIgnored private var lastOpenedToday: LocalDate?
    @ObservationIgnored private var metadataRequested: Set<String> = []
    @ObservationIgnored var onWeekLoaded: ((MenuSource, MenuWeek) -> Void)?

    init(settings: AppSettings, repository: MenuRepository, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.repository = repository
        self.now = now
        let today = LocalDate(now())
        self.today = today
        self.day = DayNavigator(skipWeekends: settings.skipWeekends).initialDay(today: today)
    }

    var navigator: DayNavigator { DayNavigator(skipWeekends: source?.provider == .rutgersFoodPro || source?.district == "rutgers" ? false : settings.skipWeekends) }
    var source: MenuSource? { settings.source }
    var isShowingDefaultDay: Bool { day == navigator.initialDay(today: today) }

    /// The next day in the loaded week that has food, for the "Next menu" button.
    var nextMenuDay: LocalDate? {
        week?.days.first { $0.date > day && $0.hasFood }?.date
    }

    // MARK: Actions

    /// Called every time the menu window opens. Jumps back to today after midnight or
    /// after a long sleep, then refreshes if the cached copy is old.
    func panelWillOpen() {
        today = LocalDate(now())
        if lastOpenedToday != today {
            lastOpenedToday = today
            day = navigator.initialDay(today: today)
        }
        load()
        restoreMenuTypesIfNeeded()
    }

    private func restoreMenuTypesIfNeeded() {
        guard let source, source.provider == .nutrislice, source.school.menuTypes.isEmpty,
              metadataRequested.insert(source.placeKey).inserted else { return }
        Task {
            guard let school = try? await repository.client.schools(district: source.district).first(where: { $0.slug == source.school.slug }),
                  var selected = settings.source, selected.placeKey == source.placeKey else { return }
            selected.school = school
            settings.source = selected
        }
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
        menuFilter = ""
        expandedItemID = nil
        load()
    }

    func refresh() { load(force: true) }

    func select(menuType: MenuType) {
        guard var source = settings.source, source.menuType != menuType else { return }
        source.menuType = menuType
        settings.source = source
        sourceDidChange()
    }

    func select(place: MenuSource) {
        settings.source = place
        expandedItemID = nil
        sourceDidChange()
    }

    var topPicks: [MenuItem] {
        guard case .menu(var day) = phase else { return [] }
        if source?.provider == .rutgersFoodPro && !settings.avoidedAllergens.isEmpty {
            for i in day.sections.indices { day.sections[i].items.removeAll { !verifiedRecipes.contains($0.foodID) } }
        }
        return settings.pickGoal.top(in: day, avoiding: settings.avoidedAllergens)
    }

    /// Whether the "Top picks" group earns its space: only when enough items have
    /// protein data that a short list of the best ones is a real shortcut. While
    /// FoodPro nutrition is still loading for a large menu, keep its place.
    var showsTopPicks: Bool {
        guard case .menu(let day) = phase else { return false }
        if nutritionLoading && source?.provider == .rutgersFoodPro && day.items.count >= 10 { return true }
        return settings.pickGoal.showsGroup(in: day, avoiding: settings.avoidedAllergens)
    }

    func sourceDidChange() {
        menuFilter = ""
        expandedItemID = nil
        week = nil
        staleNotice = nil
        load()
        restoreMenuTypesIfNeeded()
    }

    private func move(by count: Int) {
        go(to: navigator.step(from: day, by: count))
    }

    // MARK: Loading

    func load(force: Bool = false) {
        nutritionTask?.cancel()
        nutritionLoading = false
        nutritionNotice = nil
        verifiedRecipes = []
        loadGeneration += 1
        let generation = loadGeneration
        guard let source = settings.source else {
            phase = .needsSetup
            isRefreshing = false
            return
        }
        let day = day

        // Paint instantly from the week already in memory when we can.
        if let week, week.day(day) != nil {
            apply(week, source: source)
        } else { phase = .loading }
        isRefreshing = true

        Task {
            var painted = self.week?.day(day) != nil
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
                loadNutrition()
            } catch {
                guard generation == loadGeneration else { return }
                staleNotice = nil
                if !painted { phase = .failed(error) } else { staleNotice = Self.staleMessage(for: error, savedAt: nil) }
            }
        }
    }

    func loadNutrition() {
        nutritionTask?.cancel()
        nutritionGeneration += 1
        let nutritionID = nutritionGeneration
        guard let source, source.provider == .rutgersFoodPro, case .menu(let initial) = phase else { return }
        let generation = loadGeneration
        nutritionLoading = true
        nutritionNotice = nil
        nutritionTask = Task {
            defer { if generation == loadGeneration && nutritionID == nutritionGeneration { nutritionLoading = false } }
            do {
                var enriched = try await repository.foodPro.enriched(initial, source: source)
                guard !Task.isCancelled, generation == loadGeneration else { return }
                for item in enriched.items where await repository.foodPro.hasLabel(item.foodID) {
                    verifiedRecipes.insert(item.foodID)
                }
                guard !Task.isCancelled, generation == loadGeneration, nutritionID == nutritionGeneration else { return }
                phase = .menu(enriched)
                if !settings.avoidedAllergens.isEmpty {
                    // Report has no allergens: check labels in ranking order until
                    // five safe choices are known. Unknown labels never enter Top picks.
                    for candidate in settings.pickGoal.top(in: enriched, avoiding: [], limit: enriched.items.count) {
                        guard !Task.isCancelled, generation == loadGeneration else { return }
                        _ = try await repository.foodPro.details(candidate, source: source, day: enriched.date)
                        guard !Task.isCancelled, generation == loadGeneration else { return }
                        verifiedRecipes.insert(candidate.foodID)
                        enriched = await repository.foodPro.applyingCached(to: enriched)
                        guard !Task.isCancelled, generation == loadGeneration, nutritionID == nutritionGeneration else { return }
                        phase = .menu(enriched)
                        if topPicks.count >= 5 { break }
                    }
                }
            } catch {
                guard !Task.isCancelled, generation == loadGeneration else { return }
                if ProcessInfo.processInfo.arguments.contains("--http-diagnostics") {
                    FileHandle.standardError.write(Data("Nutrition error: \(error)\n".utf8))
                }
                nutritionNotice = "Some nutrition could not load. Reopen the menu to try again."
            }
        }
    }

    func loadDetails(_ id: String?) {
        guard let id, let source, source.provider == .rutgersFoodPro,
              case .menu(let current) = phase, let item = current.items.first(where: { $0.id == id }) else { return }
        let generation = loadGeneration
        Task {
            do {
                _ = try await repository.foodPro.details(item, source: source, day: current.date)
                guard generation == loadGeneration, case .menu(let displayed) = phase else { return }
                verifiedRecipes.insert(item.foodID)
                let updated = await repository.foodPro.applyingCached(to: displayed)
                guard generation == loadGeneration else { return }
                phase = .menu(updated)
            } catch {
                guard generation == loadGeneration else { return }
                nutritionNotice = "Couldn’t load this label. Try again after a short wait."
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
