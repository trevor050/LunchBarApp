import Foundation

/// Everything needed to fetch one menu: a district, one of its schools, and a menu type.
public struct MenuSource: Codable, Hashable, Sendable {
    public var provider: MenuProviderKind { providerKind ?? .nutrislice }
    private var providerKind: MenuProviderKind?
    public var placeKey: String { "\(provider.rawValue)/\(district)/\(school.slug)" }

    /// The district's Nutrislice subdomain, e.g. `middlesex` for `middlesex.nutrislice.com`.
    public var district: String
    public var districtName: String?
    public var school: School
    public var menuType: MenuType

    public init(district: String, districtName: String? = nil, school: School, menuType: MenuType, provider: MenuProviderKind = .nutrislice) {
        self.providerKind = provider == .nutrislice ? nil : provider
        self.district = district
        self.districtName = districtName
        self.school = school
        self.menuType = menuType
    }

    /// Stable identifier used for cache keys and favorites bookkeeping.
    public var key: String { provider == .nutrislice ? "\(district)/\(school.slug)/\(menuType.slug)" : "\(placeKey)/\(menuType.slug)" }

    /// The public web page for this menu, for "Open in browser".
    public func webURL(on day: LocalDate? = nil) -> URL? {
        if provider == .rutgersFoodPro { return RutgersFoodPro.menuURL(source: self, day: day ?? LocalDate(Date())) }
        var string = "https://\(district).nutrislice.com/menu/\(school.slug)/\(menuType.slug)"
        if let day { string += "/\(day.isoString)" }
        return URL(string: string)
    }
}

public struct School: Codable, Hashable, Sendable, Identifiable {
    public var id: String { slug }
    public var slug: String
    public var name: String
    public var menuTypes: [MenuType]

    public init(slug: String, name: String, menuTypes: [MenuType] = []) {
        self.slug = slug
        self.name = name
        self.menuTypes = menuTypes
    }
}

public struct MenuType: Codable, Hashable, Sendable, Identifiable {
    public var id: String { slug }
    public var slug: String
    public var name: String

    public init(slug: String, name: String) {
        self.slug = slug
        self.name = name
    }
}

/// What a user typed or pasted into the "district or menu link" field.
public struct MenuLink: Equatable, Sendable {
    public var district: String
    public var schoolSlug: String?
    public var menuTypeSlug: String?
    public var date: LocalDate?

    public init(district: String, schoolSlug: String? = nil, menuTypeSlug: String? = nil, date: LocalDate? = nil) {
        self.district = district
        self.schoolSlug = schoolSlug
        self.menuTypeSlug = menuTypeSlug
        self.date = date
    }

    /// Accepts any of:
    /// - a bare district slug: `middlesex`
    /// - a district host: `middlesex.nutrislice.com`, `middlesex.api.nutrislice.com`
    /// - a menu link: `https://middlesex.nutrislice.com/menu/middlesex-high/lunch/2026-11-10`
    /// - an API link: `https://middlesex.api.nutrislice.com/menu/api/weeks/school/middlesex-high/menu-type/lunch/2026/11/10/`
    public static func parse(_ input: String) -> MenuLink? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Bare slug: letters, digits and dashes only.
        if trimmed.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]*$"#, options: .regularExpression) != nil {
            return MenuLink(district: trimmed.lowercased())
        }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme),
              let host = components.host?.lowercased(),
              host.hasSuffix(".nutrislice.com") else {
            return nil
        }

        var labels = host.split(separator: ".").map(String.init)
        labels.removeLast(2) // "nutrislice", "com"
        if labels.last == "api" { labels.removeLast() }
        guard labels.count == 1, let district = labels.first, !district.isEmpty,
              !["www", "lookup", "api"].contains(district) else {
            return nil
        }

        var link = MenuLink(district: district)
        let path = components.path.split(separator: "/").map(String.init)

        if let schoolIndex = path.firstIndex(of: "school"), path.indices.contains(schoolIndex + 1) {
            // API style: .../school/{school}/menu-type/{type}/{yyyy}/{mm}/{dd}
            link.schoolSlug = path[schoolIndex + 1]
            if let typeIndex = path.firstIndex(of: "menu-type"), path.indices.contains(typeIndex + 1) {
                link.menuTypeSlug = path[typeIndex + 1]
                let rest = Array(path.dropFirst(typeIndex + 2))
                if rest.count >= 3, let y = Int(rest[0]), let m = Int(rest[1]), let d = Int(rest[2]) {
                    link.date = LocalDate(iso: String(format: "%04d-%02d-%02d", y, m, d))
                }
            }
        } else if let menuIndex = path.firstIndex(of: "menu") {
            // Web style: /menu/{school}/{type}[/print-menu][/{yyyy-mm-dd}]
            let rest = path.dropFirst(menuIndex + 1).filter { $0 != "print-menu" }
            let reserved: Set<String> = ["home", "menus-eula", "api"]
            if let school = rest.first, !reserved.contains(school) {
                link.schoolSlug = school
                if rest.count > 1 { link.menuTypeSlug = rest[rest.startIndex + 1] }
                if let last = rest.last, let date = LocalDate(iso: last) { link.date = date }
            }
        }

        if link.date == nil, let dateQuery = components.queryItems?.first(where: { $0.name == "date" })?.value {
            link.date = LocalDate(iso: dateQuery)
        }
        return link
    }
}
