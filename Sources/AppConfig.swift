import Foundation

enum ConfigError: LocalizedError {
    case missingKey(String)
    case invalidURL(String)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .missingKey(let key):
            return "Configuration missing required key \(key)"
        case .invalidURL(let value):
            return "Invalid URL in configuration: \(value)"
        case .fileNotFound:
            return "Configuration file not found"
        }
    }
}

struct AppConfig {
    let apiOrigin: URL
    let schoolSlug: String
    let menuTypeSlug: String

    private static let originKey = "NUTRISLICE_ORIGIN"
    private static let schoolKey = "NUTRISLICE_SCHOOL_SLUG"
    private static let menuKey = "NUTRISLICE_MENU_TYPE"
    private static let expectedKeys: Set<String> = [originKey, schoolKey, menuKey]

    static func load() throws -> AppConfig {
        // 1. Environment variables take precedence so users can inject values at launch
        let env = ProcessInfo.processInfo.environment
        if expectedKeys.isSubset(of: Set(env.keys)) {
            return try makeConfig(from: env)
        }

        // 2. Search for dotenv-style files in common locations
        let fileManager = FileManager.default
        let searchPaths: [URL] = [
            URL(fileURLWithPath: "./.env"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".lunchbar.env"),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("LunchBarApp")
                .appendingPathComponent("config.env")
        ]

        for path in searchPaths {
            if let envString = try? String(contentsOf: path, encoding: .utf8) {
                let values = parseEnv(envString)
                if expectedKeys.isSubset(of: Set(values.keys)) {
                    return try makeConfig(from: values)
                }
            }
        }

        throw ConfigError.fileNotFound
    }

    private static func makeConfig(from values: [String: String]) throws -> AppConfig {
        guard let originString = values[originKey], !originString.isEmpty else {
            throw ConfigError.missingKey(originKey)
        }
        guard let originURL = URL(string: originString) else {
            throw ConfigError.invalidURL(originString)
        }
        guard let school = values[schoolKey], !school.isEmpty else {
            throw ConfigError.missingKey(schoolKey)
        }
        guard let menu = values[menuKey], !menu.isEmpty else {
            throw ConfigError.missingKey(menuKey)
        }

        return AppConfig(apiOrigin: originURL, schoolSlug: school, menuTypeSlug: menu)
    }

    private static func parseEnv(_ contents: String) -> [String: String] {
        contents
            .split(whereSeparator: { $0.isNewline })
            .reduce(into: [String: String]()) { result, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      !trimmed.hasPrefix("#"),
                      let separator = trimmed.firstIndex(of: "=") else {
                    return
                }

                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
                let valueStart = trimmed.index(after: separator)
                var value = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces)

                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value.removeFirst()
                    value.removeLast()
                }
                result[key] = value
            }
    }
}
