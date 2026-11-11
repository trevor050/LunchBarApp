import Foundation
import Testing
@testable import LunchKit

@Suite("Dates and day navigation")
struct DateAndNavigationTests {
    let friday = LocalDate(year: 2026, month: 11, day: 13)
    let saturday = LocalDate(year: 2026, month: 11, day: 14)
    let sunday = LocalDate(year: 2026, month: 11, day: 15)
    let monday = LocalDate(year: 2026, month: 11, day: 16)

    @Test func isoParsing() {
        #expect(LocalDate(iso: "2026-11-10") == LocalDate(year: 2026, month: 11, day: 10))
        #expect(LocalDate(iso: "2026-02-30") == nil)
        #expect(LocalDate(iso: "2026-1-5") == nil)
        #expect(LocalDate(iso: "") == nil)
        #expect(LocalDate(year: 2026, month: 3, day: 7).isoString == "2026-03-07")
    }

    @Test func arithmeticAcrossBoundaries() {
        #expect(LocalDate(year: 2026, month: 12, day: 31).adding(days: 1) == LocalDate(year: 2027, month: 1, day: 1))
        #expect(LocalDate(year: 2028, month: 2, day: 28).adding(days: 1) == LocalDate(year: 2028, month: 2, day: 29))
        #expect(LocalDate(year: 2026, month: 3, day: 1).adding(days: -1) == LocalDate(year: 2026, month: 2, day: 28))
        #expect(friday.days(until: monday) == 3)
    }

    @Test func weekdaysAndWeekStart() {
        #expect(sunday.weekday == 1)
        #expect(saturday.weekday == 7)
        #expect(saturday.isWeekend && sunday.isWeekend && !friday.isWeekend)
        // Nutrislice weeks start on Sunday.
        #expect(friday.weekStart == LocalDate(year: 2026, month: 11, day: 8))
        #expect(sunday.weekStart == sunday)
        #expect(LocalDate(year: 2027, month: 1, day: 1).weekStart == LocalDate(year: 2026, month: 12, day: 27))
    }

    @Test("Converting from Date respects the calendar's time zone")
    func timeZones() throws {
        // 2026-11-10 03:30 UTC is still Nov 9 in New York.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-10T03:30:00Z"))
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(LocalDate(instant, calendar: newYork) == LocalDate(year: 2026, month: 11, day: 9))
        #expect(LocalDate(instant, calendar: .gregorianUTC) == LocalDate(year: 2026, month: 11, day: 10))
    }

    @Test("Arrows skip weekends when enabled")
    func skippingWeekends() {
        let nav = DayNavigator(skipWeekends: true)
        #expect(nav.step(from: friday, by: 1) == monday)
        #expect(nav.step(from: monday, by: -1) == friday)
        #expect(nav.step(from: friday, by: 2) == LocalDate(year: 2026, month: 11, day: 17))
        #expect(nav.step(from: saturday, by: -1) == friday)
    }

    @Test("Arrows visit every day when weekend skipping is off")
    func everyDay() {
        let nav = DayNavigator(skipWeekends: false)
        #expect(nav.step(from: friday, by: 1) == saturday)
        #expect(nav.step(from: monday, by: -1) == sunday)
        #expect(nav.step(from: friday, by: 0) == friday)
    }

    @Test("The popover opens on Monday during a weekend")
    func initialDay() {
        #expect(DayNavigator(skipWeekends: true).initialDay(today: saturday) == monday)
        #expect(DayNavigator(skipWeekends: true).initialDay(today: sunday) == monday)
        #expect(DayNavigator(skipWeekends: true).initialDay(today: friday) == friday)
        #expect(DayNavigator(skipWeekends: false).initialDay(today: saturday) == saturday)
    }
}
