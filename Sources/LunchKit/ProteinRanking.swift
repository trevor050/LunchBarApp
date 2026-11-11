import Foundation

public enum ProteinRanking: String, CaseIterable, Codable, Sendable {
    case perServing, per100Calories
    public var title: String { self == .perServing ? "Grams per serving" : "Protein per 100 calories" }
    public var heading: String { self == .perServing ? "g / serving" : "g / 100 cal" }

    public func score(_ item: MenuItem) -> Double? {
        guard let protein = item.protein, protein.isFinite, protein > 0 else { return nil }
        if self == .perServing { return protein }
        guard let calories = item.calories, calories > 0 else { return nil }
        return protein * 100 / Double(calories)
    }

    public func top(in day: MenuDay, avoiding allergens: Set<Allergen>, limit: Int = 5) -> [MenuItem] {
        var seen = Set<String>()
        return day.sections.flatMap { section in section.items.map { item in
            var copy = item; copy.category = section.title ?? item.category; return copy
        } }.filter {
            score($0) != nil && $0.warnings(avoiding: allergens).isEmpty && Self.isStandalone($0)
        }.sorted {
            let a = score($0)!, b = score($1)!
            if a != b { return a > b }
            if $0.providerName != $1.providerName { return $0.providerName < $1.providerName }
            return $0.id < $1.id
        }.filter { seen.insert($0.foodID.isEmpty ? $0.id : $0.foodID).inserted }.prefix(max(0, limit)).map { $0 }
    }

    /// Fewest rankable items for which a separate "Top protein" group adds anything.
    public static let minimumRankedForGroup = 8

    /// Whether a group of the top `limit` items is worth showing above the menu.
    /// It is not when few items have protein data, or when the group would hold
    /// most of the menu (a two-item lunch would simply be listed twice).
    public func showsGroup(in day: MenuDay, avoiding allergens: Set<Allergen>, limit: Int = 5) -> Bool {
        let ranked = top(in: day, avoiding: allergens, limit: Int.max).count
        return ranked >= max(Self.minimumRankedForGroup, limit + 1) && day.items.count >= limit * 2
    }

    /// Only <=2 oz portions at explicitly ingredient/build-your-own stations.
    /// EACH/SLICE portions, larger portions and ordinary entree stations stay eligible.
    /// This is a ranking rule only; it never removes anything from the full menu.
    public static func isStandalone(_ item: MenuItem) -> Bool {
        let station = (item.category ?? "").lowercased()
        let build = ["condiment", "topping", "cook to order", "build your own", "build-your-own", "omelet", "omelette", "noodle bar", "salad bar", "cantina sides"].contains { station.contains($0) }
        guard build, let serving = item.servingSize?.uppercased(), serving.contains("OZ") else { return true }
        let amount = serving.split(separator: " ").first.map(String.init) ?? ""
        let parts = amount.split(separator: "/").compactMap { Double($0) }
        let ounces: Double? = parts.count == 2 && parts[1] > 0 ? parts[0] / parts[1] : Double(amount)
        return ounces.map { $0 > 2 } ?? true
    }
}

extension MenuItem {
    public var protein: Double? { nutrition.first { $0.name.lowercased() == "protein" && $0.unit == "g" }?.amount }
}
