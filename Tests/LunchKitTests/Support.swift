import Foundation
@testable import LunchKit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name])
        }
        return try Data(contentsOf: url)
    }

    static let middlesexWeek = "week-middlesex-high-lunch-2026-11-08"
    static let elkRapidsThanksgivingWeek = "week-elk-rapids-high-lunch-2026-11-22"
    static let salemKeizerWeek = "week-salkeiz-auburn-lunch-2026-11-08"
    static let middlesexSchools = "schools-middlesex"
    static let middlesexSettings = "settings-middlesex"
}

extension MenuSource {
    static let middlesexLunch = MenuSource(
        district: "middlesex",
        school: School(slug: "middlesex-high", name: "Middlesex High"),
        menuType: MenuType(slug: "lunch", name: "Lunch")
    )
}

/// Records requests and replies from a closure. Never touches the network.
final class StubLoader: HTTPLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let respond: @Sendable (URLRequest) throws -> (Data, Int)

    init(respond: @escaping @Sendable (URLRequest) throws -> (Data, Int)) {
        self.respond = respond
    }

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _requests.append(request) }
        let (data, status) = try respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

/// A clock tests can move forward.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(by interval: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(interval) }
    }
}
