import Testing
@testable import LunchKit

@Suite("Pasted links and district names")
struct MenuLinkTests {
    @Test(arguments: ["middlesex", "  Middlesex \n", "middlesex.nutrislice.com", "https://middlesex.nutrislice.com/", "middlesex.api.nutrislice.com"])
    func districtOnly(input: String) {
        #expect(MenuLink.parse(input) == MenuLink(district: "middlesex"))
    }

    @Test func webMenuLink() {
        let link = MenuLink.parse("https://middlesex.nutrislice.com/menu/middlesex-high/lunch/2026-11-10")
        #expect(link == MenuLink(district: "middlesex", schoolSlug: "middlesex-high", menuTypeSlug: "lunch",
                                 date: LocalDate(year: 2026, month: 11, day: 10)))
    }

    @Test func webMenuLinkWithoutDateOrType() {
        #expect(MenuLink.parse("https://dysart.nutrislice.com/menu/asante-preparatory-academy/breakfast")
                == MenuLink(district: "dysart", schoolSlug: "asante-preparatory-academy", menuTypeSlug: "breakfast"))
        #expect(MenuLink.parse("salkeiz.nutrislice.com/menu/auburn-elementary")
                == MenuLink(district: "salkeiz", schoolSlug: "auburn-elementary"))
    }

    @Test func printMenuLink() {
        let link = MenuLink.parse("https://elkrapidsschools.nutrislice.com/menu/elk-rapids-high-school/lunch/print-menu/2026-11-23")
        #expect(link?.schoolSlug == "elk-rapids-high-school")
        #expect(link?.menuTypeSlug == "lunch")
        #expect(link?.date == LocalDate(year: 2026, month: 11, day: 23))
    }

    @Test func apiLink() {
        let link = MenuLink.parse("https://middlesex.api.nutrislice.com/menu/api/weeks/school/middlesex-high/menu-type/breakfast/2026/11/10/")
        #expect(link == MenuLink(district: "middlesex", schoolSlug: "middlesex-high", menuTypeSlug: "breakfast",
                                 date: LocalDate(year: 2026, month: 11, day: 10)))
    }

    @Test(arguments: ["", "   ", "https://example.com/menu/x/lunch", "https://www.nutrislice.com/", "https://lookup.nutrislice.com/en/",
                      "https://a.b.nutrislice.com/", "not a url at all"])
    func rejectsNonMenus(input: String) {
        #expect(MenuLink.parse(input) == nil)
    }

    @Test func homePageIsNotASchool() {
        #expect(MenuLink.parse("https://middlesex.nutrislice.com/menu/home") == MenuLink(district: "middlesex"))
    }

    @Test func webURLRoundTrip() {
        let url = MenuSource.middlesexLunch.webURL(on: LocalDate(year: 2026, month: 11, day: 10))
        #expect(url?.absoluteString == "https://middlesex.nutrislice.com/menu/middlesex-high/lunch/2026-11-10")
        #expect(MenuLink.parse(url!.absoluteString)?.schoolSlug == "middlesex-high")
    }
}
