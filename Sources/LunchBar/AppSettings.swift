import Foundation
import LunchKit
import Observation

enum TextSize: String, CaseIterable, Codable, Identifiable {
    case standard, large, extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.15
        case .extraLarge: 1.3
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var source: MenuSource? {
        didSet { save(source, for: .source) }
    }

    var skipWeekends: Bool {
        didSet { defaults.set(skipWeekends, forKey: Key.skipWeekends.rawValue) }
    }

    /// Nil means the user cleared the shortcut.
    var hotKey: HotKeyCombo? {
        didSet {
            save(hotKey, for: .hotKey)
            defaults.set(hotKey == nil, forKey: Key.hotKeyCleared.rawValue)
        }
    }

    var textSize: TextSize {
        didSet { defaults.set(textSize.rawValue, forKey: Key.textSize.rawValue) }
    }

    var avoidedAllergens: Set<Allergen> {
        didSet { save(avoidedAllergens.map(\.rawValue).sorted(), for: .avoidedAllergens) }
    }

    /// Normalized name -> name as first seen on a menu.
    var favorites: [String: String] {
        didSet { save(favorites, for: .favorites) }
    }

    var notifyFavorites: Bool {
        didSet { defaults.set(notifyFavorites, forKey: Key.notifyFavorites.rawValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        source = Self.load(MenuSource.self, defaults, .source)
        skipWeekends = defaults.object(forKey: Key.skipWeekends.rawValue) as? Bool ?? true
        if defaults.bool(forKey: Key.hotKeyCleared.rawValue) {
            hotKey = nil
        } else {
            hotKey = Self.load(HotKeyCombo.self, defaults, .hotKey) ?? .default
        }
        textSize = defaults.string(forKey: Key.textSize.rawValue).flatMap(TextSize.init(rawValue:)) ?? .standard
        avoidedAllergens = Set((Self.load([String].self, defaults, .avoidedAllergens) ?? []).compactMap(Allergen.init(rawValue:)))
        favorites = Self.load([String: String].self, defaults, .favorites) ?? [:]
        notifyFavorites = defaults.bool(forKey: Key.notifyFavorites.rawValue)
    }

    var favoriteKeys: Set<String> { Set(favorites.keys) }

    func isFavorite(_ item: MenuItem) -> Bool {
        favorites[Favorites.normalize(item.name)] != nil
    }

    func toggleFavorite(_ item: MenuItem) {
        let key = Favorites.normalize(item.name)
        if favorites[key] == nil {
            favorites[key] = item.name
        } else {
            favorites[key] = nil
        }
    }

    // MARK: Persistence

    private enum Key: String {
        case source, skipWeekends, hotKey, hotKeyCleared, textSize, avoidedAllergens, favorites, notifyFavorites
    }

    private func save<T: Encodable>(_ value: T?, for key: Key) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        defaults.set(data, forKey: key.rawValue)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ defaults: UserDefaults, _ key: Key) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Reads the `.env`-style config used by LunchBarApp 1.x so existing installs keep
/// working after the upgrade. Only consulted when no school has been picked yet.
enum LegacyConfig {
    static func importSource(environment: [String: String] = ProcessInfo.processInfo.environment) -> MenuSource? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files = [
            home.appending(path: "Library/Application Support/LunchBarApp/config.env"),
            home.appending(path: ".lunchbar.env")
        ]
        var candidates = [environment]
        candidates += files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.map(parse)
        for values in candidates {
            if let source = source(from: values) { return source }
        }
        return nil
    }

    static func source(from values: [String: String]) -> MenuSource? {
        guard let origin = values["NUTRISLICE_ORIGIN"],
              let school = values["NUTRISLICE_SCHOOL_SLUG"], !school.isEmpty,
              let menu = values["NUTRISLICE_MENU_TYPE"], !menu.isEmpty,
              let link = MenuLink.parse(origin) else {
            return nil
        }
        return MenuSource(
            district: link.district,
            school: School(slug: school, name: prettify(school)),
            menuType: MenuType(slug: menu, name: prettify(menu))
        )
    }

    static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            result[key] = value
        }
        return result
    }

    private static func prettify(_ slug: String) -> String {
        slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
