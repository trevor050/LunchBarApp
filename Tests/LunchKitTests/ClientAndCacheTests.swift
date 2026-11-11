import Foundation
import Testing
@testable import LunchKit

@Suite("API client")
struct ClientTests {
    @Test func weekURLUsesTheWeekStart() {
        let url = NutrisliceClient.weekURL(source: .middlesexLunch, containing: LocalDate(year: 2026, month: 11, day: 12))
        #expect(url?.absoluteString ==
            "https://middlesex.api.nutrislice.com/menu/api/weeks/school/middlesex-high/menu-type/lunch/2026/11/08/")
    }

    @Test func discoveryURLs() {
        #expect(NutrisliceClient.schoolsURL(district: "salkeiz")?.absoluteString == "https://salkeiz.api.nutrislice.com/menu/api/schools/")
        #expect(NutrisliceClient.settingsURL(district: "salkeiz")?.absoluteString
                == "https://salkeiz.api.nutrislice.com/menu/api/settings/?format=json")
        #expect(NutrisliceClient.baseURL(district: "evil.com/x") == nil)
        #expect(NutrisliceClient.baseURL(district: "") == nil)
    }

    @Test func sendsUserAgent() async throws {
        let data = try Fixture.data(Fixture.middlesexWeek)
        let loader = StubLoader { _ in (data, 200) }
        let week = try await NutrisliceClient(loader: loader).week(source: .middlesexLunch, containing: LocalDate(year: 2026, month: 11, day: 10))
        #expect(week.days.count == 7)
        #expect(loader.requests.first?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("LunchBar/") == true)
    }

    @Test("HTTP and network failures map to friendly errors")
    func errorMapping() async {
        let client404 = NutrisliceClient(loader: StubLoader { _ in (Data(), 404) })
        await #expect(throws: NutrisliceError.menuNotFound) {
            try await client404.week(source: .middlesexLunch, containing: LocalDate(year: 2026, month: 11, day: 10))
        }
        await #expect(throws: NutrisliceError.districtNotFound("nowhere")) {
            try await client404.schools(district: "nowhere")
        }

        let client500 = NutrisliceClient(loader: StubLoader { _ in (Data("oops".utf8), 503) })
        await #expect(throws: NutrisliceError.server(status: 503)) {
            try await client500.week(source: .middlesexLunch, containing: LocalDate(year: 2026, month: 11, day: 10))
        }

        let offline = NutrisliceClient(loader: StubLoader { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: NutrisliceError.offline) {
            try await offline.week(source: .middlesexLunch, containing: LocalDate(year: 2026, month: 11, day: 10))
        }

        let noHost = NutrisliceClient(loader: StubLoader { _ in throw URLError(.cannotFindHost) })
        await #expect(throws: NutrisliceError.districtNotFound("typo")) {
            try await noHost.schools(district: "typo")
        }

        let garbage = NutrisliceClient(loader: StubLoader { _ in (Data("<html>".utf8), 200) })
        await #expect(throws: NutrisliceError.invalidData) {
            try await garbage.schools(district: "middlesex")
        }
    }
}

@Suite("Caching")
struct CacheTests {
    let tuesday = LocalDate(year: 2026, month: 11, day: 10)
    let thursday = LocalDate(year: 2026, month: 11, day: 12)

    func makeRepository(loader: StubLoader, clock: TestClock, directory: URL? = nil) -> MenuRepository {
        MenuRepository(
            client: NutrisliceClient(loader: loader),
            cache: MenuCache(directory: directory),
            maxAge: 3600,
            now: { clock.now }
        )
    }

    @Test("Days in the same week share one request until the copy goes stale")
    func freshCacheAvoidsNetwork() async throws {
        let data = try Fixture.data(Fixture.middlesexWeek)
        let loader = StubLoader { _ in (data, 200) }
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let repo = makeRepository(loader: loader, clock: clock)

        _ = try await repo.week(source: .middlesexLunch, containing: tuesday)
        _ = try await repo.week(source: .middlesexLunch, containing: thursday)
        #expect(loader.requests.count == 1)

        clock.advance(by: 3601)
        _ = try await repo.week(source: .middlesexLunch, containing: thursday)
        #expect(loader.requests.count == 2)

        _ = try await repo.week(source: .middlesexLunch, containing: thursday, forceRefresh: true)
        #expect(loader.requests.count == 3)
    }

    @Test("When the network fails, the saved week is returned with the error")
    func staleFallback() async throws {
        let data = try Fixture.data(Fixture.middlesexWeek)
        let online = OnlineSwitch()
        let loader = StubLoader { _ in
            guard online.isOn else { throw URLError(.notConnectedToInternet) }
            return (data, 200)
        }
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let repo = makeRepository(loader: loader, clock: clock)

        let first = try await repo.week(source: .middlesexLunch, containing: tuesday)
        #expect(first.refreshError == nil)

        online.isOn = false
        clock.advance(by: 7200)
        let second = try await repo.week(source: .middlesexLunch, containing: tuesday)
        #expect(second.refreshError == .offline)
        #expect(second.week == first.week)
        #expect(second.fetchedAt == first.fetchedAt)

        // A week we never saw has nothing to fall back on.
        await #expect(throws: NutrisliceError.offline) {
            try await repo.week(source: .middlesexLunch, containing: tuesday.adding(days: 7))
        }
    }

    @Test("Weeks persist to disk and survive a new cache instance")
    func diskPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LunchKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let week = try MenuParser.week(from: Fixture.data(Fixture.middlesexWeek))
        let key = MenuCache.key(source: .middlesexLunch, weekStart: week.start)
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

        await MenuCache(directory: directory).store(CachedWeek(week: week, fetchedAt: fetchedAt), for: key)
        let reloaded = await MenuCache(directory: directory).week(for: key)
        #expect(reloaded?.week == week)
        #expect(reloaded?.fetchedAt == fetchedAt)

        let cache = MenuCache(directory: directory)
        await cache.prune(olderThan: week.start.adding(days: 30))
        #expect(await cache.week(for: key) == nil)
    }

    @Test("Concurrent requests for one week share a single download")
    func coalescing() async throws {
        let data = try Fixture.data(Fixture.middlesexWeek)
        let loader = StubLoader { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return (data, 200)
        }
        let repo = makeRepository(loader: loader, clock: TestClock(Date()))
        async let a = repo.week(source: .middlesexLunch, containing: tuesday)
        async let b = repo.week(source: .middlesexLunch, containing: thursday)
        _ = try await (a, b)
        #expect(loader.requests.count == 1)
    }

    @Test func freshness() {
        let fetched = Date(timeIntervalSince1970: 1000)
        let cached = CachedWeek(week: MenuWeek(start: tuesday.weekStart, days: []), fetchedAt: fetched)
        #expect(cached.isFresh(now: fetched.addingTimeInterval(10), maxAge: 60))
        #expect(!cached.isFresh(now: fetched.addingTimeInterval(61), maxAge: 60))
        // A clock that jumped backwards shouldn't make a copy "fresh forever".
        #expect(!cached.isFresh(now: fetched.addingTimeInterval(-10), maxAge: 60))
    }
}

final class OnlineSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    var isOn: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

@Suite("Allergens and favorites")
struct AllergenTests {
    let item = MenuItem(
        id: "1", foodID: "1", name: "Pasta Alfredo with Chicken & Broccoli",
        allergens: ["Milk", "Wheat", "May Contain Soy", "Processed in a facility that also processes Sesame", "Shellfish"]
    )

    @Test func flagsAvoidedAllergens() {
        let warnings = item.warnings(avoiding: [.milk, .soy, .sesame, .peanuts, .fish, .shellfish])
        #expect(warnings.map(\.allergen) == [.milk, .shellfish, .soy, .sesame])
        #expect(warnings.first { $0.allergen == .milk }?.isPrecautionary == false)
        #expect(warnings.first { $0.allergen == .soy }?.isPrecautionary == true)
        #expect(warnings.first { $0.allergen == .sesame }?.isPrecautionary == true)
        #expect(item.warnings(avoiding: []).isEmpty)
    }

    @Test func favoritesMatchByNormalizedName() {
        #expect(Favorites.normalize("  Pasta Alfredo w/ Chicken & Broccoli!") == "pasta alfredo w chicken broccoli")
        #expect(Favorites.normalize("Crème Brûlée") == "creme brulee")

        let day = MenuDay(date: LocalDate(year: 2026, month: 11, day: 12), sections: [
            MenuSection(id: "a", title: nil, items: [item, item])
        ])
        let favorites: Set = [Favorites.normalize("pasta alfredo with chicken & broccoli")]
        #expect(Favorites.matches(in: day, favorites: favorites).count == 1)
        #expect(Favorites.matches(in: day, favorites: []).isEmpty)
    }
}
