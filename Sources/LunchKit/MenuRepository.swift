import Foundation

/// The result of asking for a week: what to show, and whether it's live.
public struct WeekResult: Sendable, Equatable {
    public var week: MenuWeek
    public var fetchedAt: Date
    /// Set when the network request failed and `week` came from the cache.
    public var refreshError: NutrisliceError?

    public var isFromCacheAfterFailure: Bool { refreshError != nil }
}

/// Coordinates the API client and the cache.
///
/// Policy:
/// - A cached week younger than `maxAge` is returned without touching the network.
/// - Older (or forced) loads hit the network; on failure, the stale copy is returned
///   with the error attached so the UI can say "offline, showing saved menu".
/// - Concurrent requests for the same week share one network call.
public actor MenuRepository {
    public let client: NutrisliceClient
    public let cache: MenuCache
    public let maxAge: TimeInterval
    private let now: @Sendable () -> Date
    private var inFlight: [String: Task<CachedWeek, any Error>] = [:]

    public init(
        client: NutrisliceClient,
        cache: MenuCache,
        maxAge: TimeInterval = 60 * 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.cache = cache
        self.maxAge = maxAge
        self.now = now
    }

    /// Cached copy only; never touches the network. Used to paint instantly.
    public func cachedWeek(source: MenuSource, containing day: LocalDate) async -> CachedWeek? {
        await cache.week(for: MenuCache.key(source: source, weekStart: day.weekStart))
    }

    public func week(source: MenuSource, containing day: LocalDate, forceRefresh: Bool = false) async throws(NutrisliceError) -> WeekResult {
        let key = MenuCache.key(source: source, weekStart: day.weekStart)
        let cached = await cache.week(for: key)

        if !forceRefresh, let cached, cached.isFresh(now: now(), maxAge: maxAge) {
            return WeekResult(week: cached.week, fetchedAt: cached.fetchedAt, refreshError: nil)
        }

        do {
            let fresh = try await download(source: source, day: day, key: key)
            return WeekResult(week: fresh.week, fetchedAt: fresh.fetchedAt, refreshError: nil)
        } catch {
            let mapped = (error as? NutrisliceError) ?? .invalidData
            if let cached {
                return WeekResult(week: cached.week, fetchedAt: cached.fetchedAt, refreshError: mapped)
            }
            throw mapped
        }
    }

    private func download(source: MenuSource, day: LocalDate, key: String) async throws -> CachedWeek {
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let client = client
        let cache = cache
        let now = now
        let task = Task<CachedWeek, any Error> {
            let week = try await client.week(source: source, containing: day)
            let cached = CachedWeek(week: week, fetchedAt: now())
            await cache.store(cached, for: key)
            return cached
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
}
