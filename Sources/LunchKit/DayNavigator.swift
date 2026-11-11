import Foundation

/// Pure rules for moving between menu days.
public struct DayNavigator: Sendable, Equatable {
    /// When true, Saturdays and Sundays are skipped by the arrows and by the
    /// "first day to show" logic. Most K-12 schools want this; dining halls don't.
    public var skipWeekends: Bool

    public init(skipWeekends: Bool) {
        self.skipWeekends = skipWeekends
    }

    /// The day the popover should open on. On a weekend (with skipping on) this is
    /// the coming Monday, so the glanceable view is useful instead of empty.
    public func initialDay(today: LocalDate) -> LocalDate {
        guard skipWeekends, today.isWeekend else { return today }
        return step(from: today, by: 1)
    }

    /// Moves `count` days forward (or backward when negative), skipping weekends if enabled.
    public func step(from day: LocalDate, by count: Int) -> LocalDate {
        guard count != 0 else { return day }
        let direction = count > 0 ? 1 : -1
        var remaining = abs(count)
        var current = day
        while remaining > 0 {
            current = current.adding(days: direction)
            if skipWeekends && current.isWeekend { continue }
            remaining -= 1
        }
        return current
    }
}
