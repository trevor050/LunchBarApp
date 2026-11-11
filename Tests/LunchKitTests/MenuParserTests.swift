import Foundation
import Testing
@testable import LunchKit

@Suite("Menu parsing")
struct MenuParserTests {
    @Test("A normal school week has seven days, food on weekdays only")
    func middlesexWeek() throws {
        let week = try MenuParser.week(from: Fixture.data(Fixture.middlesexWeek))
        #expect(week.start == LocalDate(year: 2026, month: 11, day: 8))
        #expect(week.days.count == 7)
        #expect(week.days.map(\.date) == (0..<7).map { week.start.adding(days: $0) })

        let sunday = try #require(week.day(LocalDate(year: 2026, month: 11, day: 8)))
        #expect(!sunday.hasFood)

        let tuesday = try #require(week.day(LocalDate(year: 2026, month: 11, day: 10)))
        #expect(tuesday.items.map(\.name) == ["Korean BBQ Beef Quesadilla", "Szechuan Broccoli"])
        #expect(tuesday.holiday == nil)
    }

    @Test("Food details: calories, serving size, allergens and nutrition rows")
    func itemDetails() throws {
        let week = try MenuParser.week(from: Fixture.data(Fixture.middlesexWeek))
        let items = week.days.flatMap(\.items)
        let item = try #require(items.first { $0.name == "Korean BBQ Beef Quesadilla" })
        #expect(item.calories != nil)
        #expect(!item.nutrition.isEmpty)
        #expect(item.nutrition.first?.name == "Total Fat")
        #expect(item.nutrition.contains { $0.name == "Saturated Fat" && $0.isSubRow })
        #expect(!item.allergens.isEmpty)
        #expect(item.dietaryTags.isEmpty)
    }

    @Test("Section titles become sections, holidays become the day's holiday text")
    func sectionsAndHolidays() throws {
        let week = try MenuParser.week(from: Fixture.data(Fixture.elkRapidsThanksgivingWeek))

        let monday = try #require(week.day(LocalDate(year: 2026, month: 11, day: 23)))
        #expect(monday.sections.first?.title == "American Classics")
        #expect(monday.hasFood)
        #expect(monday.holiday == nil)

        let thanksgiving = try #require(week.day(LocalDate(year: 2026, month: 11, day: 26)))
        #expect(!thanksgiving.hasFood)
        #expect(thanksgiving.holiday == "Thanksgiving")
    }

    @Test("Highlight icons are dietary tags, not allergens")
    func dietaryTags() throws {
        let week = try MenuParser.week(from: Fixture.data(Fixture.salemKeizerWeek))
        let items = week.days.flatMap(\.items)
        let tags = Set(items.flatMap(\.dietaryTags))
        #expect(tags.isSuperset(of: ["Vegetarian", "Vegan", "Halal"]))
        #expect(!items.flatMap(\.allergens).contains("Vegan"))
        // Vitamin D is reported in mcg (the old app read the wrong key).
        #expect(items.contains { item in item.nutrition.contains { $0.name == "Vitamin D" && $0.unit == "mcg" } })
    }

    @Test("Empty sections are dropped and blank text lines ignored")
    func blankEntries() throws {
        let json = """
        {"start_date":"2026-11-08","days":[{"date":"2026-11-09","menu_items":[
          {"id":1,"position":0,"is_section_title":true,"text":"Empty Station","food":null},
          {"id":2,"position":1,"is_section_title":true,"text":"Entrees","food":null},
          {"id":3,"position":2,"is_section_title":false,"text":"","food":{"id":9,"name":"  Pizza  "}},
          {"id":4,"position":3,"is_section_title":false,"text":"   ","food":null},
          {"id":5,"position":4,"is_section_title":false,"text":"Early dismissal","food":null}
        ]}]}
        """
        let week = try MenuParser.week(from: Data(json.utf8))
        let day = try #require(week.days.first)
        #expect(day.sections.count == 1)
        #expect(day.sections[0].title == "Entrees")
        #expect(day.items.map(\.name) == ["Pizza"])
        #expect(day.notes == ["Early dismissal"])
    }

    @Test("Tolerates missing fields and rejects non-JSON")
    func robustness() throws {
        let week = try MenuParser.week(from: Data(#"{"days":[{"date":"2026-11-09"},{"date":"nope"}]}"#.utf8))
        #expect(week.days.count == 1)
        #expect(week.start == LocalDate(year: 2026, month: 11, day: 8))
        #expect(throws: MenuParser.ParseError.invalidJSON) {
            try MenuParser.week(from: Data("<html>".utf8))
        }
    }

    @Test("Malformed entries are skipped instead of failing the whole week")
    func lossyArrays() throws {
        let json = """
        {"days":[42,"junk",{"date":"2026-11-09","menu_items":[null,7,{"id":"a,b-sr1-foods","position":1,"food":{"id":"x","name":"Smart Recipe Bowl"}},
          {"id":3,"position":"not a number","food":{"name":"Broken"}},{"id":4,"position":2,"food":{"id":5,"name":"Apple"}}]}]}
        """
        let week = try MenuParser.week(from: Data(json.utf8))
        let day = try #require(week.days.first)
        #expect(day.items.map(\.name) == ["Smart Recipe Bowl", "Apple"])
        #expect(day.items.first?.id == "a,b-sr1-foods")
    }

    @Test("Schools list is parsed and sorted with menu types")
    func schools() throws {
        let schools = try MenuParser.schools(from: Fixture.data(Fixture.middlesexSchools))
        #expect(schools.map(\.name) == schools.map(\.name).sorted())
        let high = try #require(schools.first { $0.slug == "middlesex-high" })
        #expect(high.name == "Middlesex High")
        #expect(high.menuTypes.map(\.slug).starts(with: ["lunch", "breakfast"]))
    }

    @Test("District name comes from the settings endpoint")
    func districtName() throws {
        #expect(MenuParser.districtName(from: try Fixture.data(Fixture.middlesexSettings)) == "Middlesex Borough School District")
        #expect(MenuParser.districtName(from: Data("{}".utf8)) == nil)
    }
}
