import Foundation

/// What the "Top picks" group ranks a menu by. Each goal is one number from the
/// published nutrition, ranked high-to-low or low-to-high. Rules and limits are
/// documented in docs/research/top-picks.md.
public enum PickGoal: String, CaseIterable, Codable, Sendable {
    case highProtein, leanProtein, lowCalorie, lowCarb, highFiber, lowSugar, lowSodium

    public var title: String {
        switch self {
        case .highProtein: "High protein"
        case .leanProtein: "Lean protein"
        case .lowCalorie: "Low calorie"
        case .lowCarb: "Low carb"
        case .highFiber: "High fiber"
        case .lowSugar: "Low sugar"
        case .lowSodium: "Low sodium"
        }
    }

    /// What the number on each row means.
    public var unitDescription: String {
        switch self {
        case .highProtein: "g protein"
        case .leanProtein: "g protein / 100 cal"
        case .lowCalorie: "calories"
        case .lowCarb: "g carbs"
        case .highFiber: "g fiber"
        case .lowSugar: "g sugar"
        case .lowSodium: "mg sodium"
        }
    }

    /// The migrated value of the old two-mode protein setting.
    public static func migrating(proteinRanking raw: String?) -> PickGoal? {
        switch raw {
        case "perServing": .highProtein
        case "per100Calories": .leanProtein
        default: nil
        }
    }

    /// Highest first (protein, fiber) or lowest first (everything else).
    public var prefersHigh: Bool { self == .highProtein || self == .leanProtein || self == .highFiber }

    /// Minimum calories for the "low" goals, so the answer is the lightest real
    /// meal or side rather than a condiment, a drink or a garnish.
    public static let mealMinimumCalories = 120
    /// Lean protein needs a real amount of protein, not a 5-calorie garnish.
    public static let leanMinimumProtein = 10.0

    /// The value a row shows and the list is ranked by, or nil if the item has no
    /// usable data for this goal.
    public func value(_ item: MenuItem) -> Double? {
        func nutrient(_ names: [String], unit: String) -> Double? {
            item.nutrition.first { names.contains($0.name.lowercased()) && $0.unit == unit }?.amount
        }
        let value: Double?
        switch self {
        case .highProtein: value = item.protein.flatMap { $0 > 0 ? $0 : nil }
        case .leanProtein:
            guard let protein = item.protein, protein >= Self.leanMinimumProtein, let calories = item.calories, calories > 0 else { return nil }
            value = protein * 100 / Double(calories)
        case .lowCalorie: value = item.calories.map(Double.init)
        case .lowCarb: value = nutrient(["total carbohydrate", "total carbohydrates", "carbohydrates"], unit: "g")
        case .highFiber: value = nutrient(["dietary fiber", "fiber"], unit: "g").flatMap { $0 > 0 ? $0 : nil }
        case .lowSugar: value = nutrient(["total sugars", "sugars", "sugar"], unit: "g")
        case .lowSodium: value = nutrient(["sodium"], unit: "mg")
        }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Whether an item can be ranked for this goal at all.
    public func isEligible(_ item: MenuItem) -> Bool {
        guard value(item) != nil, Self.isStandalone(item) else { return false }
        if prefersHigh { return true }
        guard let calories = item.calories, calories >= Self.mealMinimumCalories else { return false }
        return Self.isMealOrSide(item)
    }

    public func top(in day: MenuDay, avoiding allergens: Set<Allergen>, limit: Int = 5) -> [MenuItem] {
        var seen = Set<String>()
        let high = prefersHigh
        return day.sections.flatMap { section in section.items.map { item in
            var copy = item; copy.category = section.title ?? item.category; return copy
        } }.filter {
            isEligible($0) && $0.warnings(avoiding: allergens).isEmpty
        }.sorted {
            let a = value($0)!, b = value($1)!
            if a != b { return high ? a > b : a < b }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }.filter { seen.insert($0.foodID.isEmpty ? $0.id : $0.foodID).inserted }.prefix(max(0, limit)).map { $0 }
    }

    /// Fewest rankable items for which a separate "Top picks" group adds anything.
    public static let minimumRankedForGroup = 8

    /// Whether a group of the top `limit` items is worth showing above the menu.
    /// It is not when few items have data for the goal, or when the group would
    /// hold most of the menu (a two-item lunch would simply be listed twice).
    public func showsGroup(in day: MenuDay, avoiding allergens: Set<Allergen>, limit: Int = 5) -> Bool {
        let ranked = top(in: day, avoiding: allergens, limit: Int.max).count
        return ranked >= max(Self.minimumRankedForGroup, limit + 1) && day.items.count >= limit * 2
    }

    /// Only <=2 oz portions at explicitly ingredient/build-your-own stations are
    /// excluded. EACH/SLICE portions, larger portions and ordinary entree stations
    /// stay eligible. This is a ranking rule only; it never hides anything from the
    /// full menu.
    public static func isStandalone(_ item: MenuItem) -> Bool {
        let station = (item.category ?? "").lowercased()
        let build = ["condiment", "topping", "cook to order", "build your own", "build-your-own", "omelet", "omelette", "noodle bar", "salad bar", "cantina sides"].contains { station.contains($0) }
        guard build, let serving = item.servingSize?.uppercased(), serving.contains("OZ") else { return true }
        let amount = serving.split(separator: " ").first.map(String.init) ?? ""
        let parts = amount.split(separator: "/").compactMap { Double($0) }
        let ounces: Double? = parts.count == 2 && parts[1] > 0 ? parts[0] / parts[1] : Double(amount)
        return ounces.map { $0 > 2 } ?? true
    }

    /// Stations that hold drinks, sauces and add-ons rather than meals or sides.
    static let nonMealStations = ["beverage", "drink", "condiment", "topping", "dressing", "sauce", "dessert", "bakery", "sweets"]
    /// The item's main noun (last word before " with", "," or "(") for things that
    /// are not a meal or side on their own.
    static let nonMealNouns: Set<String> = [
        "milk", "juice", "water", "coffee", "tea", "soda", "lemonade", "smoothie", "drink", "beverage",
        "sauce", "dressing", "vinaigrette", "gravy", "syrup", "dip", "salsa", "ketchup", "mustard", "mayo",
        "mayonnaise", "relish", "butter", "margarine", "jelly", "jam", "spread", "hummus", "guacamole",
        "croutons", "crouton", "seasoning", "sprinkles", "topping", "toppings", "garnish",
        "cookie", "cookies", "brownie", "brownies", "cupcake", "cupcakes", "pudding", "candy", "gum", "frosting",
    ]

    /// Words that make a name a dish even when its last word is an add-on
    /// ("Fish and Chips", "Chicken Sandwich with Ketchup").
    static let dishWords: Set<String> = [
        "sandwich", "burger", "wrap", "bowl", "pizza", "pasta", "salad", "soup", "chicken", "beef", "pork",
        "turkey", "fish", "salmon", "tuna", "shrimp", "tofu", "taco", "tacos", "burrito", "quesadilla", "sub",
        "rice", "noodles", "curry", "stew", "chili", "omelet", "eggs",
    ]
    /// Ingredients wherever they appear in the name, even next to a dish word
    /// ("Pork Sausage Crumbles", "Olive and Canola Oil Blend").
    static let ingredientWords: Set<String> = ["oil", "crumbles"]
    /// Snacks unless the name also names a dish ("Fish and Chips").
    static let snackWords: Set<String> = ["chip", "chips"]

    /// Plausibly a main or a side: not a drink, sauce, dressing, topping, snack,
    /// dessert or single add-on, judged by station and by the dish's main noun.
    public static func isMealOrSide(_ item: MenuItem) -> Bool {
        let station = (item.category ?? "").lowercased()
        if nonMealStations.contains(where: { station.contains($0) }) { return false }
        var name = item.name.lowercased()
        for separator in [" with ", " w/ ", ",", "("] {
            if let range = name.range(of: separator) { name = String(name[..<range.lowerBound]) }
        }
        let words = name.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains(where: ingredientWords.contains) { return false }
        if words.contains(where: dishWords.contains) { return true }
        if words.contains(where: snackWords.contains) { return false }
        return !nonMealNouns.contains(words.last ?? "")
    }
}

extension MenuItem {
    public var protein: Double? { nutrition.first { $0.name.lowercased() == "protein" && $0.unit == "g" }?.amount }
}
