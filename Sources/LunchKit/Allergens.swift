import Foundation

/// The nine major US food allergens. Users pick the ones they avoid; items that
/// mention them get flagged.
public enum Allergen: String, CaseIterable, Codable, Sendable, Identifiable {
    case milk, egg, fish, shellfish, treeNuts, peanuts, wheat, soy, sesame

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .milk: "Milk"
        case .egg: "Egg"
        case .fish: "Fish"
        case .shellfish: "Shellfish"
        case .treeNuts: "Tree Nuts"
        case .peanuts: "Peanuts"
        case .wheat: "Wheat"
        case .soy: "Soy"
        case .sesame: "Sesame"
        }
    }

    /// Lowercased words that identify this allergen inside a district's free-text label.
    var keywords: [String] {
        switch self {
        case .milk: ["milk", "dairy"]
        case .egg: ["egg"]
        case .fish: ["fish"]
        case .shellfish: ["shellfish", "crustacean"]
        case .treeNuts: ["tree nut", "treenut"]
        case .peanuts: ["peanut"]
        case .wheat: ["wheat", "gluten"]
        case .soy: ["soy"]
        case .sesame: ["sesame"]
        }
    }

    public func matches(_ label: String) -> Bool {
        let text = label.lowercased()
        if self == .fish, text.contains("shellfish"), !text.replacingOccurrences(of: "shellfish", with: "").contains("fish") {
            return false
        }
        return keywords.contains { text.contains($0) }
    }
}

/// How an item relates to one allergen the user avoids.
public struct AllergenWarning: Hashable, Sendable {
    public var allergen: Allergen
    /// True for "May contain..." / "Processed in a facility..." statements.
    public var isPrecautionary: Bool
}

public extension MenuItem {
    func warnings(avoiding avoided: Set<Allergen>) -> [AllergenWarning] {
        guard !avoided.isEmpty else { return [] }
        var result: [Allergen: Bool] = [:] // allergen -> precautionary only
        for label in allergens {
            let lower = label.lowercased()
            let precautionary = lower.hasPrefix("may contain") || lower.contains("facility")
            for allergen in avoided where allergen.matches(label) {
                result[allergen] = (result[allergen] ?? true) && precautionary
            }
        }
        return Allergen.allCases.compactMap { allergen in
            result[allergen].map { AllergenWarning(allergen: allergen, isPrecautionary: $0) }
        }
    }
}

/// Favorites are stored by normalized name so they survive menu-id churn week to week.
public enum Favorites {
    public static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func matches(in day: MenuDay, favorites: Set<String>) -> [MenuItem] {
        guard !favorites.isEmpty else { return [] }
        var seen = Set<String>()
        return day.items.filter { item in
            let key = normalize(item.name)
            return favorites.contains(key) && seen.insert(key).inserted
        }
    }
}
