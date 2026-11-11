import Foundation
import Testing
@testable import LunchKit

func rutgersFixture(_ name: String) throws -> Data {
    let url = Bundle.module.resourceURL!.appending(path: "Fixtures/Rutgers/\(name)")
    return try Data(contentsOf: url)
}

@Suite("Rutgers FoodPro HTML")
struct RutgersParserTests {
    let day = LocalDate(year: 2026, month: 11, day: 10)
    @Test(arguments: ["03-lunch", "03-dinner", "04-lunch", "04-dinner", "05-lunch", "05-dinner"])
    func hallsAndMeals(_ name: String) throws {
        let meal = name.contains("lunch") ? "Lunch" : "Dinner"
        let menu = try RutgersParser.menu(rutgersFixture(name + "-2026-11-10.html"), date: day, meal: meal)
        #expect(menu.items.count > 50)
        #expect(menu.sections.count > 3)
        #expect(Set(menu.items.map(\.id)).count == menu.items.count)
        #expect(menu.items.allSatisfy { !$0.foodID.isEmpty && $0.servingSize != nil && $0.category != nil })
    }
    @Test func unpublishedDateMustNotReuseFoodProFallback() throws {
        let menu = try RutgersParser.menu(rutgersFixture("04-empty-2026-11-26.html"), date: LocalDate(iso: "2026-11-26")!, meal: "Lunch")
        #expect(!menu.hasFood)
        #expect(menu.notes.first?.contains("published menu window") == true)
    }
    @Test func wrongMealMustNotBeRelabeled() throws {
        let menu = try RutgersParser.menu(rutgersFixture("04-lunch-2026-11-10.html"), date: day, meal: "Late Knight")
        #expect(!menu.hasFood)
    }
    @Test func label() throws {
        let label = try RutgersParser.label(rutgersFixture("04-label-eggs.html"))
        #expect(label.calories == 141)
        #expect(label.nutrients.first { $0.name == "Protein" }?.amount == 11.1)
        #expect(label.serving == "4 OZ")
        #expect(label.allergens == ["Milk", "Eggs", "Soybeans"])
        #expect(label.ingredients?.contains("WHOLE EGGS") == true)
        #expect(label.hasLabel)
    }
    @Test func reportKeepsIndividualValuesAndMissingValues() throws {
        let values = try RutgersParser.report(rutgersFixture("04-lunch-report.html"))
        #expect(values.count > 70)
        #expect(values.values.contains { $0.nutrients.contains { $0.name == "Protein" && $0.amount > 0 } })
        #expect(values.values.contains { $0.nutrients.isEmpty && $0.calories == nil })
    }
    @Test func changedMarkupFailsLoudly() {
        #expect(throws: (any Error).self) { try RutgersParser.menu(Data("<html>server maintenance</html>".utf8), date: day, meal: "Lunch") }
        #expect(throws: (any Error).self) { try RutgersParser.label(Data("<html>error</html>".utf8)) }
        #expect(throws: (any Error).self) { try RutgersParser.report(Data("<html>error</html>".utf8)) }
    }
    @Test func entitiesAndMalformedItemAreHandled() throws {
        let real = String(decoding: try rutgersFixture("04-lunch-2026-11-10.html"), as: UTF8.self)
        let entity = real.replacingOccurrences(of: "FRENCH FRIES", with: "FRIES &amp; CHEESE")
        let menu = try RutgersParser.menu(Data(entity.utf8), date: day, meal: "Lunch")
        #expect(menu.items.contains { $0.providerName.contains("& CHEESE") && $0.name.contains("Fries & Cheese") })
        let broken = real.replacingOccurrences(of: "RecNumAndPort=", with: "changed=")
        #expect(throws: (any Error).self) { try RutgersParser.menu(Data(broken.utf8), date: day, meal: "Lunch") }
    }
}

@Suite("Protein ranking")
struct ProteinTests {
    func item(_ name: String, protein: Double? = nil, calories: Int? = nil, station: String = "Entrees", serving: String = "1 EACH", allergens: [String] = []) -> MenuItem {
        MenuItem(id: name, foodID: name, name: name, category: station, calories: calories, servingSize: serving,
                 allergens: allergens, nutrition: protein.map { [Nutrient(name: "Protein", amount: $0, unit: "g")] } ?? [])
    }
    func day(_ items: [MenuItem]) -> MenuDay { MenuDay(date: LocalDate(iso: "2026-11-10")!, sections: [MenuSection(id: "a", title: nil, items: items)]) }
    @Test func modesAndMissingData() {
        let menu = day([item("Big", protein: 40, calories: 800), item("Lean", protein: 30, calories: 150), item("Unknown"), item("No calories", protein: 20), item("Zero", protein: 0, calories: 0)])
        #expect(ProteinRanking.perServing.top(in: menu, avoiding: []).map(\.name) == ["Big", "Lean", "No calories"])
        #expect(ProteinRanking.per100Calories.top(in: menu, avoiding: []).map(\.name) == ["Lean", "Big"])
        #expect(ProteinRanking.perServing.top(in: day([item("Unknown")]), avoiding: []).isEmpty)
    }
    @Test func excludesAllergensAndIngredientPortionsButKeepsEntrees() {
        let menu = day([item("Cheese", protein: 50, station: "Cook to order bar", serving: "1 OZ"), item("Chicken", protein: 30, serving: "4 OZ"), item("Eggs", protein: 20, station: "Cook to order bar", serving: "4 OZ"), item("Milk", protein: 40, allergens: ["Milk"])])
        #expect(ProteinRanking.perServing.top(in: menu, avoiding: [.milk]).map(\.name) == ["Chicken", "Eggs"])
        #expect(ProteinRanking.isStandalone(item("Small entree", protein: 10, serving: "2 OZ")))
        #expect(ProteinRanking.isStandalone(item("Grilled chicken", protein: 30, station: "Toppings", serving: "6 OZ")))
        #expect(ProteinRanking.isStandalone(item("Chicken entree", protein: 30, station: "Cook to order", serving: "1 EACH")))
        #expect(!ProteinRanking.isStandalone(item("Cheddar", protein: 7, station: "Salad Bar", serving: "1 OZ")))
        #expect(ProteinRanking.isStandalone(item("Chicken salad", protein: 30, station: "Salad Bar", serving: "3 OZ")))
    }
    @Test func deterministicTiesDeduplicationAndFiveLimit() {
        var items = ["F", "E", "D", "C", "B", "A"].map { item($0, protein: 10, calories: 100) }
        var duplicate = items[0]; duplicate.id = "other-station"; items.append(duplicate)
        #expect(ProteinRanking.perServing.top(in: day(items), avoiding: []).map(\.name) == ["A", "B", "C", "D", "E"])
        #expect(ProteinRanking.per100Calories.top(in: day(items.reversed()), avoiding: []).map(\.name) == ["A", "B", "C", "D", "E"])
        #expect(ProteinRanking.perServing.top(in: day([item("Bad", protein: .infinity)]), avoiding: []).isEmpty)
    }
    @Test func singleSourceMigrationAndLegacyDecoding() throws {
        let old = Data(#"{"district":"middlesex","school":{"slug":"middlesex-high","name":"Middlesex High","menuTypes":[]},"menuType":{"slug":"lunch","name":"Lunch"}}"#.utf8)
        let source = try JSONDecoder().decode(MenuSource.self, from: old)
        #expect(source.provider == .nutrislice)
        #expect(source.key == "middlesex/middlesex-high/lunch")
        let hall = RutgersLocations.source(hall: RutgersLocations.foodPro[1])
        #expect(SavedPlaces.migrate(saved: nil, legacy: source) == [source])
        #expect(SavedPlaces.migrate(saved: [source, hall], legacy: source).count == 2)
        var breakfast = source; breakfast.menuType = MenuType(slug: "breakfast", name: "Breakfast")
        let places = SavedPlaces.migrate(saved: [source, hall], legacy: breakfast)
        #expect(places.count == 2)
        #expect(places[0].menuType.slug == "breakfast")
        #expect(try JSONDecoder().decode(MenuSource.self, from: JSONEncoder().encode(hall)).provider == .rutgersFoodPro)
    }
}

@Suite("FoodPro caching and request policy")
struct FoodProCacheTests {
    let date = LocalDate(iso: "2026-11-10")!
    var source: MenuSource { RutgersLocations.source(hall: RutgersLocations.foodPro[1]) }
    @Test func coldWarmAndDayMealHallIsolation() async throws {
        let menu = try rutgersFixture("04-lunch-2026-11-10.html")
        let report = try rutgersFixture("04-lunch-report.html")
        let loader = StubLoader { req in
            guard req.cachePolicy == .reloadIgnoringLocalCacheData, !req.httpShouldHandleCookies else { throw URLError(.badURL) }
            if req.httpMethod == "POST" {
                let form = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
                guard URLComponents(string: "?" + form)?.queryItems?.filter({ $0.name == "recipe" }).allSatisfy({ $0.value?.split(separator: "*").count == 3 }) == true else { throw URLError(.badURL) }
            }
            return (req.httpMethod == "POST" ? report : menu, 200)
        }
        let provider = RutgersFoodPro(loader: loader, directory: nil, spacing: 0)
        let repo = MenuRepository(client: NutrisliceClient(loader: loader), cache: MenuCache(directory: nil), foodPro: provider)
        let result = try await repo.week(source: source, containing: date)
        let enriched = try await provider.enriched(result.week.day(date)!, source: source)
        #expect(!ProteinRanking.perServing.top(in: enriched, avoiding: []).isEmpty)
        let cold = loader.requests.count
        #expect(cold == 1 + Int(ceil(Double(Set(enriched.items.map(\.foodID)).count) / 100)))
        _ = try await repo.week(source: source, containing: date)
        _ = try await provider.enriched(result.week.day(date)!, source: source)
        #expect(loader.requests.count == cold)
        #expect(loader.requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.contains("github.com/trevor050/LunchBarApp") == true })
        // A different date never reuses the same day's HTML even inside a week.
        _ = try await repo.week(source: source, containing: date.adding(days: 1))
        #expect(loader.requests.count == cold + 1)
        var other = source; other.menuType = MenuType(slug: "Dinner", name: "Dinner")
        _ = try await repo.week(source: other, containing: date)
        #expect(loader.requests.count == cold + 2)
        other = RutgersLocations.source(hall: RutgersLocations.foodPro[0])
        _ = try await repo.week(source: other, containing: date)
        #expect(loader.requests.count == cold + 3)
    }
    @Test func labelCachePersistsAndExpiresAfterThirtyDays() async throws {
        let data = try rutgersFixture("04-label-eggs.html")
        let loader = StubLoader { _ in (data, 200) }
        let clock = TestClock(Date())
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let egg = MenuItem(id: "egg", foodID: "061002*4", name: "Eggs")
        let a = RutgersFoodPro(loader: loader, directory: directory, spacing: 0, now: { clock.now })
        _ = try await a.details(egg, source: source, day: date)
        let b = RutgersFoodPro(loader: loader, directory: directory, spacing: 0, now: { clock.now })
        let restored = try await b.details(egg, source: source, day: date.adding(days: 1))
        #expect(restored.protein == 11.1)
        #expect(loader.requests.count == 1)
        clock.advance(by: 31 * 86400)
        _ = try await b.details(egg, source: source, day: date)
        #expect(loader.requests.count == 2)
    }
    @Test func backoffAndRequestCoalescing() async throws {
        let data = try rutgersFixture("04-label-eggs.html")
        let loader = StubLoader { _ in (data, 200) }
        let provider = RutgersFoodPro(loader: loader, directory: nil, spacing: 0)
        let egg = MenuItem(id: "egg", foodID: "061002*4", name: "Eggs")
        async let a = provider.details(egg, source: source, day: date)
        async let b = provider.details(egg, source: source, day: date)
        _ = try await (a, b)
        #expect(loader.requests.count == 1)
        let failed = StubLoader { _ in (Data(), 429) }
        let clock = TestClock(Date())
        let blocked = RutgersFoodPro(loader: failed, directory: nil, spacing: 0, now: { clock.now })
        _ = try? await blocked.week(source: source, containing: date)
        _ = try? await blocked.week(source: source, containing: date)
        #expect(failed.requests.count == 1)
        clock.advance(by: 31)
        _ = try? await blocked.week(source: source, containing: date)
        #expect(failed.requests.count == 2)
    }
}

@Suite("FoodPro concurrency")
struct FoodProConcurrencyTests {
    @Test func differentLabelsStaySerialized() async throws {
        let loader = ConcurrentLabelLoader(data: try rutgersFixture("04-label-eggs.html"))
        let provider = RutgersFoodPro(loader: loader, directory: nil, spacing: 0)
        let source = RutgersLocations.source(hall: RutgersLocations.foodPro[1])
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in 1...8 {
                group.addTask {
                    _ = try await provider.details(MenuItem(id: "\(id)", foodID: "\(id)*1", name: "Food"), source: source, day: LocalDate(iso: "2026-11-10")!)
                }
            }
            try await group.waitForAll()
        }
        #expect(await loader.maximumActive == 1)
        #expect(await provider.requestCount == 8)
    }
}

private actor ConcurrentLabelLoader: HTTPLoading {
    let data: Data
    var active = 0
    var maximumActive = 0
    init(data: Data) { self.data = data }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
