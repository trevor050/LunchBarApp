import Foundation

/// A calendar day with no time or time zone attached.
///
/// Nutrislice menus are keyed by plain `YYYY-MM-DD` dates. Keeping them as a
/// value type (instead of `Date`) avoids the classic midnight/DST/time-zone bugs
/// when comparing "today" with a menu day.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day that `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses `YYYY-MM-DD`. Returns nil for anything else, including impossible dates.
    public init?(iso string: String) {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        let candidate = LocalDate(year: year, month: month, day: day)
        // Round-trip through a calendar to reject things like 2026-02-30.
        guard let date = candidate.date(in: .gregorianUTC), LocalDate(date, calendar: .gregorianUTC) == candidate else {
            return nil
        }
        self = candidate
    }

    /// Start of this day in `calendar`'s time zone.
    public func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func adding(days: Int) -> LocalDate {
        let calendar = Calendar.gregorianUTC
        guard let start = date(in: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: start) else {
            return self
        }
        return LocalDate(moved, calendar: calendar)
    }

    /// Days from `self` to `other` (positive when `other` is later).
    public func days(until other: LocalDate) -> Int {
        let calendar = Calendar.gregorianUTC
        guard let a = date(in: calendar), let b = other.date(in: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// 1 = Sunday ... 7 = Saturday, matching `Calendar.component(.weekday:)`.
    public var weekday: Int {
        guard let date = date(in: .gregorianUTC) else { return 1 }
        return Calendar.gregorianUTC.component(.weekday, from: date)
    }

    public var isWeekend: Bool { weekday == 1 || weekday == 7 }

    /// Nutrislice weeks run Sunday through Saturday.
    public var weekStart: LocalDate { adding(days: -(weekday - 1)) }
}

extension Calendar {
    /// A fixed Gregorian calendar used for pure day arithmetic.
    static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
