import Foundation

/// Anything that can perform an HTTP request. `URLSession` conforms; tests use a stub.
public protocol HTTPLoading: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPLoading {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

public enum NutrisliceError: Error, Equatable, Sendable {
    /// The district subdomain doesn't exist (DNS failure or 404 on the schools list).
    case districtNotFound(String)
    /// The school or menu type is gone (404 on a week).
    case menuNotFound
    case offline
    case timedOut
    case server(status: Int)
    case invalidData

    /// Short, friendly text for the UI.
    public var message: String {
        switch self {
        case .districtNotFound(let district):
            "Couldn't find a Nutrislice district called “\(district)”."
        case .menuNotFound:
            "This menu isn't on Nutrislice anymore. Pick your school again in Settings."
        case .offline:
            "You're offline."
        case .timedOut:
            "Nutrislice is taking too long to answer."
        case .server(let status):
            "Nutrislice had a problem (HTTP \(status))."
        case .invalidData:
            "Nutrislice sent something unexpected."
        }
    }
}

/// Client for the public, unauthenticated Nutrislice menu API.
///
/// Endpoints (per district, `https://{district}.api.nutrislice.com`):
/// - `GET /menu/api/schools/`: schools and their active menu types
/// - `GET /menu/api/settings/?format=json`: district display name
/// - `GET /menu/api/weeks/school/{school}/menu-type/{type}/{yyyy}/{mm}/{dd}/`: the Sun–Sat week containing that day
public struct NutrisliceClient: Sendable {
    public static let userAgent = "LunchBar/2.0 (+https://github.com/trevor050/LunchBarApp)"

    private let loader: any HTTPLoading

    public init(loader: any HTTPLoading = NutrisliceClient.defaultSession) {
        self.loader = loader
    }

    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "application/json"]
        return URLSession(configuration: configuration)
    }()

    // MARK: URLs

    public static func baseURL(district: String) -> URL? {
        guard district.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://\(district).api.nutrislice.com/menu/api/")
    }

    public static func schoolsURL(district: String) -> URL? {
        baseURL(district: district)?.appending(path: "schools/")
    }

    public static func settingsURL(district: String) -> URL? {
        guard let base = baseURL(district: district) else { return nil }
        var components = URLComponents(url: base.appending(path: "settings/"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "format", value: "json")]
        return components?.url
    }

    public static func weekURL(source: MenuSource, containing day: LocalDate) -> URL? {
        let start = day.weekStart
        return baseURL(district: source.district)?
            .appending(path: "weeks/school/\(source.school.slug)/menu-type/\(source.menuType.slug)/")
            .appending(path: String(format: "%04d/%02d/%02d/", start.year, start.month, start.day))
    }

    // MARK: Requests

    public func schools(district: String) async throws(NutrisliceError) -> [School] {
        guard let url = Self.schoolsURL(district: district) else { throw .districtNotFound(district) }
        let data: Data
        do throws(NutrisliceError) {
            data = try await get(url)
        } catch .menuNotFound {
            throw .districtNotFound(district)
        }
        do {
            return try MenuParser.schools(from: data)
        } catch {
            throw .invalidData
        }
    }

    /// Best effort; a missing name is not an error.
    public func districtName(district: String) async -> String? {
        guard let url = Self.settingsURL(district: district),
              let data = try? await get(url) else { return nil }
        return MenuParser.districtName(from: data)
    }

    public func week(source: MenuSource, containing day: LocalDate) async throws(NutrisliceError) -> MenuWeek {
        guard let url = Self.weekURL(source: source, containing: day) else { throw .districtNotFound(source.district) }
        let data = try await get(url)
        do {
            return try MenuParser.week(from: data)
        } catch {
            throw .invalidData
        }
    }

    private func get(_ url: URL) async throws(NutrisliceError) -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loader.data(for: request)
        } catch {
            throw Self.map(error, host: url.host() ?? "")
        }
        guard let http = response as? HTTPURLResponse else { throw .invalidData }
        switch http.statusCode {
        case 200..<300: return data
        case 404: throw .menuNotFound
        default: throw .server(status: http.statusCode)
        }
    }

    static func map(_ error: any Error, host: String) -> NutrisliceError {
        guard let urlError = error as? URLError else { return .invalidData }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timedOut
        case .cannotFindHost, .dnsLookupFailed:
            let district = host.split(separator: ".").first.map(String.init) ?? host
            return .districtNotFound(district)
        case .cannotConnectToHost, .secureConnectionFailed, .badServerResponse:
            return .server(status: 0)
        default:
            return .offline
        }
    }
}
