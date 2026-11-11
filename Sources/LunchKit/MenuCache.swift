import Foundation

/// A week plus when it was downloaded.
public struct CachedWeek: Codable, Hashable, Sendable {
    /// Bump when parsed menus change shape or presentation (2: Rutgers names in
    /// normal case). Older disk copies are treated as missing and refetched.
    public static let currentFormat = 2

    public var week: MenuWeek
    public var fetchedAt: Date
    /// Absent in files written before versioning, which reads as format 1.
    public var format: Int?

    public init(week: MenuWeek, fetchedAt: Date, format: Int? = CachedWeek.currentFormat) {
        self.week = week
        self.fetchedAt = fetchedAt
        self.format = format
    }

    public var isCurrentFormat: Bool { (format ?? 1) == Self.currentFormat }

    public func isFresh(now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(fetchedAt) < maxAge && now >= fetchedAt
    }
}

/// Two-level (memory + disk) cache of menu weeks.
///
/// Menus change rarely, so one download per week per menu, refreshed at most
/// hourly while the popover is being used, is plenty. The disk copy is what
/// lets the app show something useful when the network is down.
public actor MenuCache {
    private var memory: [String: CachedWeek] = [:]
    private let directory: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// - Parameter directory: where to persist weeks. Pass nil for memory-only (tests).
    public init(directory: URL?) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "io.github.trevor050.LunchBar/weeks", directoryHint: .isDirectory)
    }

    public static func key(source: MenuSource, weekStart: LocalDate) -> String {
        "\(source.key)/\(weekStart.isoString)"
    }

    public func week(for key: String) -> CachedWeek? {
        if let hit = memory[key] { return hit }
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let cached = try? decoder.decode(CachedWeek.self, from: data),
              cached.isCurrentFormat else {
            return nil
        }
        memory[key] = cached
        return cached
    }

    public func store(_ cached: CachedWeek, for key: String) {
        memory[key] = cached
        guard let url = fileURL(for: key), let data = try? encoder.encode(cached) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func removeAll() {
        memory.removeAll()
        guard let directory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    /// Deletes weeks that ended long ago so the cache can't grow forever.
    public func prune(olderThan cutoff: LocalDate) {
        memory = memory.filter { $0.value.week.start.adding(days: 6) >= cutoff }
        guard let directory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let cached = try? decoder.decode(CachedWeek.self, from: data),
                  cached.isCurrentFormat else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            if cached.week.start.adding(days: 6) < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func fileURL(for key: String) -> URL? {
        guard let directory else { return nil }
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appending(path: String(safe) + ".json")
    }
}
