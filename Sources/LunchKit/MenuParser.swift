import Foundation

/// Turns raw Nutrislice JSON into the app's menu model.
///
/// The API is public but undocumented, so every field is treated as optional and
/// anything unexpected is skipped instead of failing the whole week.
public enum MenuParser {
    public enum ParseError: Error, Equatable {
        case invalidJSON
    }

    public static func week(from data: Data) throws -> MenuWeek {
        let dto: WeekDTO
        do {
            dto = try decoder.decode(WeekDTO.self, from: data)
        } catch {
            throw ParseError.invalidJSON
        }
        let days = (dto.days?.elements ?? []).compactMap(day(from:)).sorted { $0.date < $1.date }
        // `start_date` is the first school day (usually Monday); the API's weeks
        // really begin on Sunday, which is what cache keys and URLs use.
        let anchor = days.first?.date ?? dto.startDate.flatMap(LocalDate.init(iso:)) ?? LocalDate(Date())
        let start = anchor.weekStart
        return MenuWeek(start: start, days: days)
    }

    public static func schools(from data: Data) throws -> [School] {
        let dtos: [SchoolDTO]
        do {
            dtos = try decoder.decode(LossyArray<SchoolDTO>.self, from: data).elements
        } catch {
            throw ParseError.invalidJSON
        }
        return dtos.compactMap { dto in
            guard let slug = dto.slug, let name = dto.name else { return nil }
            let types = (dto.activeMenuTypes?.elements ?? []).compactMap { type -> MenuType? in
                guard let slug = type.slug, let name = type.name else { return nil }
                return MenuType(slug: slug, name: name)
            }
            return School(slug: slug, name: name.trimmingCharacters(in: .whitespaces), menuTypes: types)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func districtName(from data: Data) -> String? {
        guard let dto = try? decoder.decode(SettingsDTO.self, from: data) else { return nil }
        let name = dto.districtName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty ?? true) ? nil : name
    }

    // MARK: - Mapping

    static func day(from dto: DayDTO) -> MenuDay? {
        guard let dateString = dto.date, let date = LocalDate(iso: dateString) else { return nil }

        var sections: [MenuSection] = []
        var currentTitle: String?
        var currentID = "\(date.isoString)-top"
        var currentItems: [MenuItem] = []
        var holiday: String?
        var notes: [String] = []

        func closeSection() {
            if !currentItems.isEmpty {
                sections.append(MenuSection(id: currentID, title: currentTitle, items: currentItems))
            }
            currentItems = []
        }

        let entries = (dto.menuItems?.elements ?? []).sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        for entry in entries {
            let text = entry.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if entry.isSectionTitle == true || entry.isStationHeader == true {
                closeSection()
                currentTitle = text.isEmpty ? nil : text
                currentID = "\(date.isoString)-\(entry.id?.value ?? String(sections.count))"
                continue
            }

            if let food = entry.food, let item = item(from: food, entry: entry) {
                if !currentItems.contains(where: { $0.id == item.id }) { currentItems.append(item) }
                continue
            }

            guard !text.isEmpty else { continue }
            if entry.isHoliday == true {
                if holiday == nil { holiday = text }
            } else if !notes.contains(text) {
                notes.append(text)
            }
        }
        closeSection()

        return MenuDay(date: date, sections: sections, holiday: holiday, notes: notes)
    }

    static func item(from food: FoodDTO, entry: MenuItemDTO) -> MenuItem? {
        let position = entry.position ?? 0
        guard let name = food.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let icons = food.icons?.foodIcons?.elements ?? []
        // behavior 1 = "contains" style allergen icons; behavior 2 = highlight (Vegan, Halal...).
        let allergens = icons.filter { $0.isHighlight != true && $0.behavior != 2 }.compactMap(\.displayName)
        let dietary = icons.filter { $0.isHighlight == true || $0.behavior == 2 }.compactMap(\.displayName)
        let groups = (food.icons?.myplateIcons?.elements ?? []).compactMap(\.displayName)

        let nutrition = food.roundedNutritionInfo.map(nutrients(from:)) ?? []
        let calories = food.roundedNutritionInfo?.calories.map { Int($0.rounded()) }

        return MenuItem(
            id: entry.id?.value ?? food.id?.value ?? "\(position)-\(name)",
            foodID: food.id?.value ?? "",
            name: name,
            description: food.description?.nilIfBlank,
            imageURL: food.imageUrl?.nilIfBlank.flatMap(URL.init(string:)),
            category: (food.foodCategory ?? entry.category)?.nilIfBlank,
            calories: calories,
            servingSize: servingSize(food.servingSizeInfo, entry: entry),
            ingredients: food.ingredients?.nilIfBlank,
            allergens: unique(allergens),
            dietaryTags: unique(dietary),
            foodGroups: unique(groups),
            nutrition: nutrition
        )
    }

    static func servingSize(_ info: ServingSizeDTO?, entry: MenuItemDTO) -> String? {
        let amount = info?.servingSizeAmount?.nilIfBlank
        let unit = info?.servingSizeUnit?.nilIfBlank
        switch (amount, unit) {
        case let (amount?, unit?): return "\(amount) \(unit)"
        case let (amount?, nil): return amount
        default: return nil
        }
    }

    static func nutrients(from info: NutritionDTO) -> [Nutrient] {
        var rows: [Nutrient] = []
        func add(_ name: String, _ value: Double?, _ unit: String, sub: Bool = false) {
            guard let value else { return }
            rows.append(Nutrient(name: name, amount: value, unit: unit, isSubRow: sub))
        }
        add("Total Fat", info.gFat, "g")
        add("Saturated Fat", info.gSaturatedFat, "g", sub: true)
        add("Trans Fat", info.gTransFat, "g", sub: true)
        add("Cholesterol", info.mgCholesterol, "mg")
        add("Sodium", info.mgSodium, "mg")
        add("Total Carbohydrate", info.gCarbs, "g")
        add("Dietary Fiber", info.gFiber, "g", sub: true)
        add("Total Sugars", info.gSugar, "g", sub: true)
        add("Added Sugars", info.gAddedSugar, "g", sub: true)
        add("Protein", info.gProtein, "g")
        add("Vitamin D", info.mcgVitaminD, "mcg")
        add("Calcium", info.mgCalcium, "mg")
        add("Iron", info.mgIron, "mg")
        add("Potassium", info.mgPotassium, "mg")
        add("Vitamin C", info.mgVitaminC, "mg")
        return rows
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Wire format (all optional on purpose)

/// Decodes an array, silently dropping elements that don't decode.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Discard.self)
            }
        }
        self.elements = elements
    }

    /// Accepts any JSON value without reading it, so the container always advances.
    private struct Discard: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

/// Nutrislice ids are usually integers but composite recipe entries use strings.
struct FlexibleID: Decodable {
    var value: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = String(int)
        } else {
            value = try container.decode(String.self)
        }
    }
}

struct WeekDTO: Decodable {
    var startDate: String?
    var days: LossyArray<DayDTO>?
}

struct DayDTO: Decodable {
    var date: String?
    var menuItems: LossyArray<MenuItemDTO>?
}

struct MenuItemDTO: Decodable {
    var id: FlexibleID?
    var position: Int?
    var isSectionTitle: Bool?
    var isStationHeader: Bool?
    var isHoliday: Bool?
    var text: String?
    var category: String?
    var food: FoodDTO?
}

struct FoodDTO: Decodable {
    var id: FlexibleID?
    var name: String?
    var description: String?
    var imageUrl: String?
    var foodCategory: String?
    var ingredients: String?
    var servingSizeInfo: ServingSizeDTO?
    var roundedNutritionInfo: NutritionDTO?
    var icons: IconsDTO?
}

struct ServingSizeDTO: Decodable {
    var servingSizeAmount: String?
    var servingSizeUnit: String?
}

struct NutritionDTO: Decodable {
    var calories: Double?
    var gFat: Double?
    var gSaturatedFat: Double?
    var gTransFat: Double?
    var mgCholesterol: Double?
    var gCarbs: Double?
    var gFiber: Double?
    var gSugar: Double?
    var gAddedSugar: Double?
    var gProtein: Double?
    var mgSodium: Double?
    var mgPotassium: Double?
    var mgCalcium: Double?
    var mgIron: Double?
    var mgVitaminC: Double?
    var mcgVitaminD: Double?
}

struct IconsDTO: Decodable {
    var foodIcons: LossyArray<IconDTO>?
    var myplateIcons: LossyArray<IconDTO>?
}

struct IconDTO: Decodable {
    var name: String?
    var syncedName: String?
    var behavior: Int?
    var isHighlight: Bool?

    var displayName: String? {
        let value = (name ?? syncedName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }
}

struct SchoolDTO: Decodable {
    var slug: String?
    var name: String?
    var activeMenuTypes: LossyArray<MenuTypeDTO>?
}

struct MenuTypeDTO: Decodable {
    var slug: String?
    var name: String?
}

struct SettingsDTO: Decodable {
    var districtName: String?
}
