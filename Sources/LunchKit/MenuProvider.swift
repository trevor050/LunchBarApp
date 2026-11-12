import Foundation

/// Providers keep their native request granularity; both yield the same menu models.
public protocol MenuProviding: Sendable {
    func week(source: MenuSource, containing day: LocalDate) async throws(NutrisliceError) -> MenuWeek
}

extension NutrisliceClient: MenuProviding {}

public enum MenuProviderKind: String, Codable, Sendable {
    case nutrislice, rutgersFoodPro
}

/// Saved places are independent of meal selection. Old single-source JSON still decodes.
public enum SavedPlaces {
    public static func migrate(saved: [MenuSource]?, legacy: MenuSource?) -> [MenuSource] {
        var result: [MenuSource] = []
        for source in (saved ?? []) + (legacy.map { [$0] } ?? []) {
            if let index = result.firstIndex(where: { $0.placeKey == source.placeKey }) {
                if source.placeKey == legacy?.placeKey { result[index] = source }
            } else { result.append(source) }
        }
        return result
    }
}

public enum RutgersLocations {
    public static let meals = ["Breakfast", "Lunch", "Dinner", "Late Knight"].map { MenuType(slug: $0, name: $0) }
    /// Confirmed FoodPro IDs only. The current official Atrium link goes to Nutrislice.
    public static let foodPro = [
        School(slug: "03", name: "Livingston Dining Commons", menuTypes: meals),
        School(slug: "04", name: "Busch Dining Hall", menuTypes: meals),
        School(slug: "05", name: "Neilson Dining Hall", menuTypes: meals)
    ]
    public static func source(hall: School, meal: MenuType? = nil) -> MenuSource {
        MenuSource(district: "rutgers", districtName: "Rutgers University Dining", school: hall,
                   menuType: meal ?? meals[1], provider: .rutgersFoodPro)
    }
}
