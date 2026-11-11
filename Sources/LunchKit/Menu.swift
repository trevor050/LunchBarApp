import Foundation

/// One Nutrislice week (Sunday through Saturday) for a single school and menu type.
public struct MenuWeek: Codable, Hashable, Sendable {
    public var start: LocalDate
    public var days: [MenuDay]

    public init(start: LocalDate, days: [MenuDay]) {
        self.start = start
        self.days = days
    }

    public func day(_ date: LocalDate) -> MenuDay? {
        days.first { $0.date == date }
    }
}

public struct MenuDay: Codable, Hashable, Sendable, Identifiable {
    public var id: LocalDate { date }
    public var date: LocalDate
    public var sections: [MenuSection]
    /// Set when the district marked the day as a holiday ("Thanksgiving", "No School", ...).
    public var holiday: String?
    /// Free-text lines the district added that aren't food or holidays.
    public var notes: [String]

    public init(date: LocalDate, sections: [MenuSection], holiday: String? = nil, notes: [String] = []) {
        self.date = date
        self.sections = sections
        self.holiday = holiday
        self.notes = notes
    }

    public var items: [MenuItem] { sections.flatMap(\.items) }
    public var hasFood: Bool { sections.contains { !$0.items.isEmpty } }
}

public struct MenuSection: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Station or section name, e.g. "Entrees". Nil for the untitled leading section.
    public var title: String?
    public var items: [MenuItem]

    public init(id: String, title: String?, items: [MenuItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct MenuItem: Codable, Hashable, Sendable, Identifiable {
    /// The menu-entry id (unique within a week even when a food repeats).
    public var id: String
    public var foodID: String
    public var name: String
    public var description: String?
    public var imageURL: URL?
    public var category: String?
    public var calories: Int?
    public var servingSize: String?
    public var ingredients: String?
    /// Allergen statements exactly as the district wrote them ("Milk", "May contain Soy").
    public var allergens: [String]
    /// Positive dietary highlights ("Vegetarian", "Vegan", "Halal").
    public var dietaryTags: [String]
    /// MyPlate food groups ("Grain", "Protein").
    public var foodGroups: [String]
    public var nutrition: [Nutrient]

    public init(
        id: String, foodID: String, name: String, description: String? = nil, imageURL: URL? = nil,
        category: String? = nil, calories: Int? = nil, servingSize: String? = nil, ingredients: String? = nil,
        allergens: [String] = [], dietaryTags: [String] = [], foodGroups: [String] = [], nutrition: [Nutrient] = []
    ) {
        self.id = id
        self.foodID = foodID
        self.name = name
        self.description = description
        self.imageURL = imageURL
        self.category = category
        self.calories = calories
        self.servingSize = servingSize
        self.ingredients = ingredients
        self.allergens = allergens
        self.dietaryTags = dietaryTags
        self.foodGroups = foodGroups
        self.nutrition = nutrition
    }
}

public struct Nutrient: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var amount: Double
    public var unit: String
    /// Sub-rows like "Saturated Fat" are indented under their parent on a nutrition label.
    public var isSubRow: Bool

    public init(name: String, amount: Double, unit: String, isSubRow: Bool = false) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.isSubRow = isSubRow
    }

    public var formattedAmount: String {
        let number = amount.rounded() == amount
            ? String(Int(amount))
            : String(format: "%.1f", amount)
        return "\(number) \(unit)"
    }
}
