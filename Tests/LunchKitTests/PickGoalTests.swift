import Foundation
import Testing
@testable import LunchKit

@Suite("Top picks goals")
struct PickGoalTests {
    func item(_ name: String, cal: Int? = nil, protein: Double? = nil, carbs: Double? = nil, fiber: Double? = nil,
              sugar: Double? = nil, sodium: Double? = nil, station: String = "Entrees", serving: String = "1 EACH",
              allergens: [String] = []) -> MenuItem {
        var nutrition: [Nutrient] = []
        if let protein { nutrition.append(Nutrient(name: "Protein", amount: protein, unit: "g")) }
        if let carbs { nutrition.append(Nutrient(name: "Total Carbohydrate", amount: carbs, unit: "g")) }
        if let fiber { nutrition.append(Nutrient(name: "Dietary Fiber", amount: fiber, unit: "g", isSubRow: true)) }
        if let sugar { nutrition.append(Nutrient(name: "Total Sugars", amount: sugar, unit: "g", isSubRow: true)) }
        if let sodium { nutrition.append(Nutrient(name: "Sodium", amount: sodium, unit: "mg")) }
        return MenuItem(id: name, foodID: name, name: name, category: station, calories: cal, servingSize: serving,
                        allergens: allergens, nutrition: nutrition)
    }
    func day(_ items: [MenuItem]) -> MenuDay {
        MenuDay(date: LocalDate(iso: "2026-11-11")!, sections: [MenuSection(id: "a", title: nil, items: items)])
    }
    func names(_ goal: PickGoal, _ items: [MenuItem], avoiding: Set<Allergen> = []) -> [String] {
        goal.top(in: day(items), avoiding: avoiding).map(\.name)
    }

    @Test func eachGoalRanksByItsOwnNumber() {
        let menu = [
            item("Chicken Bowl", cal: 600, protein: 40, carbs: 50, fiber: 6, sugar: 8, sodium: 900),
            item("Turkey Wrap", cal: 450, protein: 30, carbs: 40, fiber: 3, sugar: 4, sodium: 1100),
            item("Grilled Fish", cal: 250, protein: 28, carbs: 2, fiber: 0, sugar: 0, sodium: 400),
            item("Bean Chili", cal: 320, protein: 18, carbs: 45, fiber: 12, sugar: 6, sodium: 700),
            item("Garden Salad", cal: 140, protein: 4, carbs: 12, fiber: 4, sugar: 5, sodium: 150),
        ]
        #expect(names(.highProtein, menu) == ["Chicken Bowl", "Turkey Wrap", "Grilled Fish", "Bean Chili", "Garden Salad"])
        #expect(names(.leanProtein, menu) == ["Grilled Fish", "Chicken Bowl", "Turkey Wrap", "Bean Chili"]) // salad < 10 g
        #expect(names(.lowCalorie, menu) == ["Garden Salad", "Grilled Fish", "Bean Chili", "Turkey Wrap", "Chicken Bowl"])
        #expect(names(.lowCarb, menu).prefix(2) == ["Grilled Fish", "Garden Salad"])
        #expect(names(.highFiber, menu) == ["Bean Chili", "Chicken Bowl", "Garden Salad", "Turkey Wrap"]) // 0 g fiber excluded
        #expect(names(.lowSugar, menu).first == "Grilled Fish")
        #expect(names(.lowSodium, menu) == ["Garden Salad", "Grilled Fish", "Bean Chili", "Chicken Bowl", "Turkey Wrap"])
        #expect(PickGoal.lowSodium.value(menu[0]) == 900)
        #expect(PickGoal.leanProtein.value(menu[2]) == 28 * 100 / 250.0)
    }

    @Test func lowGoalsOnlyRankRealMealsAndSides() {
        let menu = [
            item("Ranch Dressing", cal: 140, carbs: 1, sugar: 1, sodium: 260),
            item("Chocolate Skim Milk", cal: 130, carbs: 22, sugar: 20, sodium: 150),
            item("Apple Juice", cal: 120, carbs: 29, sugar: 28, sodium: 10),
            item("Chocolate Chip Cookie", cal: 160, carbs: 22, sugar: 12, sodium: 110),
            item("Marinara Sauce", cal: 130, carbs: 10, sugar: 8, sodium: 400),
            item("Pickle Spear", cal: 5, carbs: 1, sugar: 0, sodium: 300),
            item("Cucumber Coins", cal: 10, carbs: 2, sugar: 1, sodium: 0),
            item("Shredded Cheddar", cal: 130, carbs: 1, sugar: 0, sodium: 180, station: "Salad Bar", serving: "1 OZ"),
            item("Lemonade", cal: 150, carbs: 40, sugar: 38, sodium: 10, station: "Beverages"),
            item("Hot Fudge", cal: 140, carbs: 20, sugar: 18, sodium: 60, station: "Toppings"),
            // Real dishes, including names that end in words that are usually add-ons.
            item("Mac and Cheese", cal: 380, carbs: 40, sugar: 5, sodium: 800),
            item("Chicken Pot Pie", cal: 420, carbs: 35, sugar: 4, sodium: 900),
            item("Grilled Cheese", cal: 350, carbs: 30, sugar: 3, sodium: 700),
            item("Chicken Sandwich with Ketchup", cal: 400, carbs: 38, sugar: 6, sodium: 850),
            item("Steamed Broccoli", cal: 120, carbs: 10, sugar: 2, sodium: 60, station: "Sides"),
        ]
        let lowCal = names(.lowCalorie, menu)
        #expect(lowCal == ["Steamed Broccoli", "Grilled Cheese", "Mac and Cheese", "Chicken Sandwich with Ketchup", "Chicken Pot Pie"])
        for goal in [PickGoal.lowCarb, .lowSugar, .lowSodium] {
            let picked = Set(names(goal, menu))
            #expect(picked == ["Steamed Broccoli", "Grilled Cheese", "Mac and Cheese", "Chicken Sandwich with Ketchup", "Chicken Pot Pie"], "\(goal)")
        }
        // High goals keep add-ons out only through the portion rule, as before.
        #expect(!PickGoal.highProtein.isEligible(item("Cheddar", cal: 110, protein: 7, station: "Salad Bar", serving: "1 OZ")))
        #expect(PickGoal.isMealOrSide(item("Peanut Butter and Jelly Sandwich")))
        #expect(!PickGoal.isMealOrSide(item("BBQ Sauce (2 oz)")))
        // Seen on Busch Dining Hall's real menu.
        for name in ["Canola Oil", "Olive and Canola Oil Blend", "Pork Sausage Crumbles", "Potato Chips Individual", "Tri Color Tortilla Chip w/ Tajin"] {
            #expect(!PickGoal.isMealOrSide(item(name)), "\(name)")
        }
        for name in ["Fish and Chips", "Grilled Chicken Montreal", "Basmati Rice", "Indian Vegetable Fried Rice", "Cole Slaw"] {
            #expect(PickGoal.isMealOrSide(item(name)), "\(name)")
        }
    }

    @Test func missingDataLeavesAnItemOutAndCanHideTheGroup() {
        let noFiber = (1...12).map { item("Dish \($0)", cal: 200 + $0, protein: Double($0) + 5, carbs: 20) }
        #expect(PickGoal.highFiber.top(in: day(noFiber), avoiding: []).isEmpty)
        #expect(!PickGoal.highFiber.showsGroup(in: day(noFiber), avoiding: []))
        #expect(!PickGoal.lowSodium.showsGroup(in: day(noFiber), avoiding: []))
        #expect(PickGoal.lowCarb.showsGroup(in: day(noFiber), avoiding: []))
        #expect(PickGoal.highProtein.showsGroup(in: day(noFiber), avoiding: []))
        // A goal value of NaN or a negative number is not data.
        #expect(PickGoal.lowSodium.value(item("Bad", cal: 200, sodium: -.infinity)) == nil)
    }

    @Test func tiesAreBrokenByNameThenIDAndDuplicatesCollapse() {
        var items = ["E", "C", "A", "D", "B", "F"].map { item("Dish \($0)", cal: 200, carbs: 10) }
        var duplicate = items[2]; duplicate.id = "another station"; items.append(duplicate)
        #expect(names(.lowCarb, items) == ["Dish A", "Dish B", "Dish C", "Dish D", "Dish E"])
        #expect(names(.lowCalorie, items.reversed()) == ["Dish A", "Dish B", "Dish C", "Dish D", "Dish E"])
    }

    @Test func avoidedAllergensStayOut() {
        let menu = [item("Cheese Pizza", cal: 280, carbs: 30, allergens: ["Milk", "Wheat"]),
                    item("May Contain Pasta", cal: 300, carbs: 40, allergens: ["May contain milk"]),
                    item("Rice Bowl", cal: 350, carbs: 60)]
        #expect(names(.lowCarb, menu, avoiding: [.milk]) == ["Rice Bowl"])
        #expect(names(.lowCarb, menu) == ["Cheese Pizza", "May Contain Pasta", "Rice Bowl"])
    }

    @Test func migratesTheOldProteinSetting() {
        #expect(PickGoal.migrating(proteinRanking: "perServing") == .highProtein)
        #expect(PickGoal.migrating(proteinRanking: "per100Calories") == .leanProtein)
        #expect(PickGoal.migrating(proteinRanking: nil) == nil)
        #expect(PickGoal.migrating(proteinRanking: "other") == nil)
    }
}
