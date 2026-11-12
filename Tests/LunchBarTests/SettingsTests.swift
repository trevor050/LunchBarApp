import Foundation
import Testing
import LunchKit
@testable import LunchBar

@MainActor
@Suite("Saved settings migration")
struct SettingsTests {
    @Test(arguments: [("perServing", PickGoal.highProtein), ("per100Calories", PickGoal.leanProtein)])
    func migratesTheOldProteinRankingToAGoal(stored: String, goal: PickGoal) {
        let name = "LunchBarSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(stored, forKey: "proteinRanking")
        #expect(AppSettings(defaults: defaults).pickGoal == goal)
        // A chosen goal wins over the old key from then on.
        AppSettings(defaults: defaults).pickGoal = .lowSodium
        #expect(AppSettings(defaults: defaults).pickGoal == .lowSodium)
        #expect(defaults.string(forKey: "proteinRanking") == stored)
    }

    @Test func freshSettingsDefaultToHighProtein() {
        let name = "LunchBarSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("garbage", forKey: "pickGoal")
        #expect(AppSettings(defaults: defaults).pickGoal == .highProtein)
    }

    @Test func migratesExistingUserDefaultsAndRestoresMultiplePlaces() throws {
        let name = "LunchBarSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let source = MenuSource(district: "middlesex", school: School(slug: "middlesex-high", name: "Middlesex High"), menuType: MenuType(slug: "lunch", name: "Lunch"))
        defaults.set(try JSONEncoder().encode(source), forKey: "source")
        defaults.set(false, forKey: "skipWeekends")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.savedPlaces == [source])
        #expect(settings.source == source)
        #expect(!settings.skipWeekends)
        #expect(settings.pickGoal == .highProtein)
        let hall = RutgersLocations.source(hall: RutgersLocations.foodPro[1])
        settings.source = hall
        settings.pickGoal = .lowCarb
        settings.stationExpansion["hall/Entrees"] = true
        let restored = AppSettings(defaults: defaults)
        #expect(restored.savedPlaces.count == 2)
        #expect(restored.source == hall)
        #expect(restored.pickGoal == .lowCarb)
        #expect(restored.stationExpansion["hall/Entrees"] == true)
        var breakfast = hall; breakfast.menuType = RutgersLocations.meals[0]
        restored.source = breakfast
        #expect(restored.savedPlaces.count == 2)
        #expect(restored.savedPlaces.last?.menuType == breakfast.menuType)
    }
}

@MainActor
@Suite("Progressive FoodPro view model")
struct FoodProViewModelTests {
    @Test func labelsGateAllergenRankingAndWarmOpenDoesNotFetch() async throws {
        let name = "LunchBarModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.source = RutgersLocations.source(hall: RutgersLocations.foodPro[1])
        settings.avoidedAllergens = [.milk]
        let loader = ModelLoader()
        let provider = RutgersFoodPro(loader: loader, directory: nil, spacing: 0)
        let repository = MenuRepository(client: NutrisliceClient(loader: loader), cache: MenuCache(directory: nil), foodPro: provider)
        let date = LocalDate(iso: "2026-11-10")!
        let model = MenuViewModel(settings: settings, repository: repository, now: { date.date()!.addingTimeInterval(3600 * 12) })
        model.panelWillOpen()
        #expect(model.isRefreshing)
        #expect(model.topPicks.isEmpty)
        for _ in 0..<400 {
            if !model.isRefreshing && !model.nutritionLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.nutritionLoading)
        #expect(model.topPicks.map(\.name) == ["Safe chicken", "Eggs"])
        guard case .menu(let day) = model.phase else { Issue.record("Expected menu"); return }
        #expect(day.items.first?.warnings(avoiding: [.milk]).isEmpty == false)
        #expect(day.items.count == 3)
        let cold = await loader.count
        #expect(cold == 5) // menu, report, three labels, including the excluded candidate
        model.panelWillOpen()
        for _ in 0..<400 {
            if !model.isRefreshing && !model.nutritionLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await loader.count == cold)
        #expect(model.topPicks.map(\.name) == ["Safe chicken", "Eggs"])
    }
}

private actor ModelLoader: HTTPLoading {
    var count = 0
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        count += 1
        let ids = ["1*4", "2*4", "3*4"]
        let names = ["Milk entree", "Safe chicken", "Eggs"]
        let proteins = [40, 30, 20]
        let html: String
        switch request.url!.lastPathComponent.lowercased() {
        case "pickmenu.aspx":
            let rows = ids.indices.map { i in
                "<fieldset><div class='col-1'><input name='recipe' value='\(ids[i])*1'><label for='\(i)'>\(names[i])</label></div><div class='col-2'>4 OZ</div><a href='label.aspx?RecNumAndPort=\(ids[i])'>Nutrition</a></fieldset>"
            }.joined()
            html = "<select name='date'><option value='pickmenu.aspx?dtdate=11/10/2026'>Today</option></select><form action='nutRpt.aspx?mealName=Lunch&dtdate=11/10/2026'><div class='menuBox'><h3>ENTREES</h3>\(rows)</div></form>"
        case "nutrpt.aspx":
            html = "<div class='nutritionBox'>" + ids.indices.map { i in
                "<div class='header-col-1'><a href='label.aspx?RecNumAndPort=\(ids[i])'>\(names[i])</a></div><div class='col-1'>Prot: \(proteins[i])g Cals: 200kcal</div>"
            }.joined() + "</div>"
        default:
            let recipe = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "RecNumAndPort" }?.value
            let index = ids.firstIndex(of: recipe ?? "") ?? 0
            let allergens = index == 0 ? "Milk" : index == 2 ? "Eggs" : "None"
            html = "<div id='nutritional-info'><div id='facts'><p>Serving Size 4 OZ</p><p>Calories 200</p></div><div id='specs'><table><tr><td>Protein \(proteins[index])g</td></tr></table></div><p>INGREDIENTS: Food</p><p>ALLERGENS: \(allergens)</p></div>"
        }
        return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
