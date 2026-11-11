import Foundation
import SwiftSoup

/// FoodPro has no stable API contract. Require known containers and item fields;
/// reject malformed/changed pages instead of quietly calling them closed.
public enum RutgersParser {
    public enum ParseError: Error { case unexpectedHTML }

    static func document(_ data: Data) throws -> Document {
        guard data.count < 8_000_000,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            throw ParseError.unexpectedHTML
        }
        return try SwiftSoup.parse(html)
    }

    public static func menu(_ data: Data, date: LocalDate, meal: String) throws -> MenuDay {
        let doc = try document(data)
        guard let form = try doc.select("form[action*=nutRpt], form[action*=nutrpt]").first(),
              let box = try form.select(".menuBox").first() else { throw ParseError.unexpectedHTML }
        // FoodPro silently falls back to breakfast for unknown meals. Never relabel it.
        let action = try form.attr("action")
        guard query(action, "mealName")?.caseInsensitiveCompare(meal) == .orderedSame,
              query(action, "dtdate").flatMap(portalDate) == date else {
            return MenuDay(date: date, sections: [], notes: ["No \(meal) menu published for this date."])
        }
        let published = try doc.select("select[name=date] option").array().contains { query(try $0.attr("value"), "dtdate").flatMap(portalDate) == date }
        guard published else { return MenuDay(date: date, sections: [], notes: ["This date is outside Rutgers’ published menu window."]) }
        var sections: [MenuSection] = []
        var title = "Menu"
        var items: [MenuItem] = []
        func close() {
            if !items.isEmpty {
                let shown = DisplayText.normalized(title)
                sections.append(MenuSection(id: title + "-\(sections.count)", title: shown, items: items, rawTitle: shown == title ? nil : title))
            }
            items = []
        }
        let fields = try box.select("fieldset")
        for node in try box.select("h3, fieldset") {
            if node.tagName() == "h3" {
                close()
                title = try node.text().trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                continue
            }
            guard let label = try node.select(".col-1 label[for]").first(),
                  let serving = try node.select(".col-2").first(),
                  let link = try node.select("a[href*=label.aspx]").first(),
                  let recipe = query(try link.attr("href"), "RecNumAndPort"), validRecipe(recipe),
                  let checkbox = try node.select("input[name=recipe]").first() else {
                throw ParseError.unexpectedHTML
            }
            let token = try checkbox.attr("value")
            guard token.hasPrefix(recipe + "*"), token.split(separator: "*").count == 3 else { throw ParseError.unexpectedHTML }
            let name = try label.text()
            guard !name.isEmpty else { throw ParseError.unexpectedHTML }
            let shownName = DisplayText.normalized(name)
            items.append(MenuItem(id: "\(title)-\(items.count)-\(recipe)", foodID: recipe, name: shownName,
                                  category: DisplayText.normalized(title), servingSize: try serving.text(), providerReference: token,
                                  rawName: shownName == name ? nil : name))
        }
        close()
        guard sections.flatMap(\.items).count == fields.count else { throw ParseError.unexpectedHTML }
        return MenuDay(date: date, sections: sections, notes: sections.isEmpty ? ["No menu published for this meal."] : [])
    }

    public static func report(_ data: Data) throws -> [String: FoodProNutrition] {
        let doc = try document(data)
        guard let box = try doc.select(".nutritionBox").first() else { throw ParseError.unexpectedHTML }
        var result: [String: FoodProNutrition] = [:]
        var recipe: String?
        var text = ""
        func close() {
            if let recipe { result[recipe] = nutrients(text, aliases: reportAliases) }
            text = ""
        }
        for child in box.children() {
            if child.hasClass("header-col-1") {
                close()
                recipe = try child.select("a[href*=label.aspx]").first().flatMap { query(try $0.attr("href"), "RecNumAndPort") }
            } else if recipe != nil { text += " " + (try child.text()) }
        }
        close()
        guard !result.isEmpty else { throw ParseError.unexpectedHTML }
        return result
    }

    public static func label(_ data: Data) throws -> FoodProNutrition {
        let doc = try document(data)
        guard let facts = try doc.select("#facts").first(),
              let specs = try doc.select("#specs table").first() else { throw ParseError.unexpectedHTML }
        var value = nutrients(try specs.text(), aliases: labelAliases)
        let factsText = try facts.text()
        value.calories = number(factsText, after: "Calories").map { Int($0.rounded()) }
        value.serving = try facts.select("p").array().map { try $0.text() }.first { $0.hasPrefix("Serving Size ") }?.replacingOccurrences(of: "Serving Size ", with: "")
        for paragraph in try doc.select("p") {
            let text = try paragraph.text()
            if text.hasPrefix("INGREDIENTS:") { value.ingredients = String(text.dropFirst("INGREDIENTS:".count)).trimmingCharacters(in: .whitespaces) }
            if text.hasPrefix("ALLERGENS:") {
                value.allergens = String(text.dropFirst("ALLERGENS:".count)).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        value.hasLabel = true
        return value
    }

    private static func portalDate(_ text: String) -> LocalDate? {
        let parts = text.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return LocalDate(iso: String(format: "%04d-%02d-%02d", parts[2], parts[0], parts[1]))
    }

    static func query(_ relative: String, _ name: String) -> String? {
        URLComponents(string: relative.replacingOccurrences(of: "&amp;", with: "&"))?.queryItems?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
    static func validRecipe(_ value: String) -> Bool {
        value.range(of: #"^\d{1,12}\*\d+(?:\.\d+|/\d+)?$"#, options: .regularExpression) != nil
    }
    static func number(_ text: String, after name: String) -> Double? {
        let pattern = NSRegularExpression.escapedPattern(for: name) + #"\s*:?\s*(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text), let value = Double(text[range]), value.isFinite else { return nil }
        return value
    }
    private static let reportAliases = [("Prot:", "Protein", "g"), ("Fat-T:", "Total Fat", "g"), ("Fat-S:", "Saturated Fat", "g"), ("TFA:", "Trans Fat", "g"), ("Carb:", "Total Carbohydrate", "g"), ("Fiber:", "Dietary Fiber", "g"), ("Sugar:", "Total Sugars", "g"), ("SugAdd:", "Added Sugars", "g"), ("Sod:", "Sodium", "mg"), ("Chol:", "Cholesterol", "mg"), ("Calc:", "Calcium", "mg"), ("Iron:", "Iron", "mg")]
    private static let labelAliases = [("Protein", "Protein", "g"), ("Total Fat", "Total Fat", "g"), ("Sat. Fat", "Saturated Fat", "g"), ("Trans Fat", "Trans Fat", "g"), ("Tot. Carb.", "Total Carbohydrate", "g"), ("Dietary Fiber", "Dietary Fiber", "g"), ("Sugars", "Total Sugars", "g"), ("Sodium", "Sodium", "mg"), ("Cholesterol", "Cholesterol", "mg")]
    private static func nutrients(_ text: String, aliases: [(String, String, String)]) -> FoodProNutrition {
        var value = FoodProNutrition()
        value.calories = number(text, after: "Cals:").map { Int($0.rounded()) }
        value.nutrients = aliases.compactMap { alias, name, unit in
            number(text, after: alias).map { Nutrient(name: name, amount: $0, unit: unit) }
        }
        return value
    }
}

public struct FoodProNutrition: Codable, Sendable {
    public var calories: Int?
    public var nutrients: [Nutrient] = []
    public var serving: String?
    public var ingredients: String?
    public var allergens: [String] = []
    public var hasLabel = false
    public var fetchedAt = Date()

    public func applying(to item: MenuItem) -> MenuItem {
        var copy = item
        copy.calories = calories ?? item.calories
        if !nutrients.isEmpty { copy.nutrition = nutrients }
        copy.servingSize = serving ?? item.servingSize
        copy.ingredients = ingredients ?? item.ingredients
        if hasLabel { copy.allergens = allergens }
        return copy
    }
}
