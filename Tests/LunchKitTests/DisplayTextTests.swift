import Foundation
import Testing
@testable import LunchKit

@Suite("Display names")
struct DisplayTextTests {
    /// Real FoodPro names and the casing we want on screen, plus a few synthetic edge cases
    /// for tokens the recorded fixtures do not contain (marked below).
    static let table: [(raw: String, shown: String)] = [
        // small words, ampersands, first/last word capitalized
        ("BAKED MACARONI AND CHEESE", "Baked Macaroni and Cheese"),
        ("BAKED MACARONI & CHEESE", "Baked Macaroni & Cheese"),
        ("TURKEY & PROVOLONE ON KAISER", "Turkey & Provolone on Kaiser"),
        ("FRESH FRUIT TO GO", "Fresh Fruit to Go"),
        ("BAO BUNS MADE TO ORDER", "Bao Buns Made to Order"),
        ("PASTA DU JOUR", "Pasta du Jour"),
        ("PICO DE GALLO", "Pico de Gallo"),
        ("COOK TO ORDER BAR", "Cook to Order Bar"),
        ("BRAISED TOFU WITH MUSHROOMS AND GINGER", "Braised Tofu with Mushrooms and Ginger"),
        ("A LA CARTE", "A la Carte"),                      // synthetic
        ("THE WORKS", "The Works"),                        // synthetic: first word stays capitalized
        ("SOUP OF THE DAY", "Soup of the Day"),            // synthetic
        ("VITAMIN A", "Vitamin A"),                        // synthetic: last word stays capitalized
        // all-caps tokens that stay
        ("BBQ PORK SANDWICH", "BBQ Pork Sandwich"),
        ("BBQ PULLED PORK", "BBQ Pulled Pork"),
        ("CTO MASTER", "CTO Master"),
        ("BLT WRAP", "BLT Wrap"),                          // synthetic
        ("NY STYLE CHEESECAKE", "NY Style Cheesecake"),    // synthetic
        ("PB&J SANDWICH", "PB&J Sandwich"),                // synthetic
        ("LTO BURGER", "LTO Burger"),                      // synthetic
        ("GF PASTA", "GF Pasta"),                          // synthetic
        ("PENNE (V)", "Penne (V)"),                        // synthetic
        ("V CHILI", "V Chili"),                            // synthetic
        // apostrophes and possessives
        ("CHEF'S SPECIAL", "Chef's Special"),
        ("HAND TOSSED MEAT LOVER'S PIZZA", "Hand Tossed Meat Lover's Pizza"),
        ("KICKIN' BUFFALO CAULIFLOWER", "Kickin' Buffalo Cauliflower"),
        ("ZA'ATAR HADDOCK WITH SESAMETAHINI", "Za'atar Haddock with Sesametahini"),
        ("GENERAL TSO'S CHICKEN", "General Tso's Chicken"),   // synthetic
        ("SHEPHERD'S PIE", "Shepherd's Pie"),                 // synthetic
        ("SHEPHERD\u{2019}S PIE", "Shepherd\u{2019}s Pie"),   // synthetic: curly apostrophe
        ("O'BRIEN POTATOES", "O'Brien Potatoes"),             // synthetic
        ("M&M'S COOKIE", "M&M's Cookie"),                     // synthetic
        // hyphens
        ("PLANT-BASED EATS", "Plant-Based Eats"),
        ("SRIRACHA SPICED PLANT-BASED SAUSAGE FLATBREAD PIZZA", "Sriracha Spiced Plant-Based Sausage Flatbread Pizza"),
        ("STIR-FRY", "Stir-Fry"),                             // synthetic
        ("MIX-AND-MATCH BOWL", "Mix-and-Match Bowl"),         // synthetic
        // slashes and parentheses
        ("BEEF W/ PEA PODS & VEGETABLES", "Beef w/ Pea Pods & Vegetables"),
        ("CHICKEN W/MUSHROOMS", "Chicken w/Mushrooms"),
        ("CHICKEN SHAWARMA W/ WARMING SPICES", "Chicken Shawarma w/ Warming Spices"),
        ("PEARL COUS COUS W/ SEARED CHERRY TOMATOES", "Pearl Cous Cous w/ Seared Cherry Tomatoes"),
        ("SALAD W/O DRESSING", "Salad w/o Dressing"),         // synthetic
        ("HOT/COLD CEREAL", "Hot/Cold Cereal"),               // synthetic
        ("TANGY PLANT-BASED SLOPPY JOE (VEGAN)", "Tangy Plant-Based Sloppy Joe (Vegan)"),
        ("(VEGAN) CHILI", "(Vegan) Chili"),                   // synthetic
        // punctuation that FoodPro leaves unspaced
        ("CHICKEN,SHRIMP, AND ANDOUILLE GUMBO SOUP", "Chicken,Shrimp, and Andouille Gumbo Soup"),
        ("ROASTED MUSHROOM, PEPPER, AND ONION", "Roasted Mushroom, Pepper, and Onion"),
        ("ST. LOUIS RIBS", "St. Louis Ribs"),                 // synthetic
        // numbers, units, fractions
        ("4\" CLUB ROLL", "4\" Club Roll"),
        ("6\" FLOUR TORTILLA", "6\" Flour Tortilla"),
        ("8 GRAIN BREAD", "8 Grain Bread"),
        ("GRILLED CHICKEN BREAST 4OZ", "Grilled Chicken Breast 4oz"),
        ("MINUTE MAID APPLE JUICE 12 OZ", "Minute Maid Apple Juice 12 oz"),
        ("MINUTE MAID ORANGE JUICE 12OZ", "Minute Maid Orange Juice 12oz"),
        ("1/2 CHICKEN", "1/2 Chicken"),                       // synthetic
        ("1/2 LB BURGER", "1/2 lb Burger"),                   // synthetic
        ("12 FL OZ WATER", "12 fl oz Water"),                 // synthetic
        ("2 EGGS", "2 Eggs"),                                 // synthetic
        ("7UP", "7UP"),                                       // synthetic: unknown alphanumeric stays
        ("3 CHEESE PIZZA", "3 Cheese Pizza"),                 // synthetic
        // odd spacing and station names
        ("BELGIAN  WAFFLES", "Belgian  Waffles"),
        ("PIZZA & PASTA", "Pizza & Pasta"),
        ("LUNCH TAKEOUT", "Lunch Takeout"),
        ("SOUPS", "Soups"),
        ("PUB SIDES", "Pub Sides"),
        ("ASIAN INSPIRED CUISINE", "Asian Inspired Cuisine"),
    ]

    @Test("Real FoodPro names read like Nutrislice names", arguments: zip(table.map(\.raw), table.map(\.shown)))
    func titleCase(_ raw: String, _ shown: String) {
        #expect(DisplayText.normalized(raw) == shown)
    }

    @Test("Text that already has lowercase letters is never touched")
    func mixedCaseIsUntouched() {
        for text in ["Philly Style Cheesesteak", "Mac and Cheese", "BBQ Chicken", "General Tso's Chicken", "McDonald's Style Fries",
                     "iPhone Cake", "Chicken (Vegan)", "PB&J", "pizza", "Entrees", "Chicken NUGGETS", "6\" Sub"] {
            #expect(DisplayText.normalized(text) == text)
        }
    }

    @Test("Strings with no letters, or a single initialism, are returned as they came")
    func nothingToDo() {
        for text in ["", " ", "12", "1/2", "&", "-- --", "BBQ", "BLT", "PB&J", "V", "GF"] {
            #expect(DisplayText.normalized(text) == text)
        }
    }

    @Test("Parsed Rutgers menus show normal case, keep the provider text, and only change letter case")
    func recordedFixtures() throws {
        var checked = 0
        for name in ["03-lunch", "03-dinner", "04-lunch", "04-dinner", "05-lunch", "05-dinner"] {
            let day = try RutgersParser.menu(rutgersFixture(name + "-2026-11-10.html"),
                                             date: LocalDate(year: 2026, month: 11, day: 10),
                                             meal: name.contains("lunch") ? "Lunch" : "Dinner")
            for section in day.sections {
                let raw = try #require(section.rawTitle)
                #expect(section.providerTitle == raw)
                #expect(section.title == DisplayText.normalized(raw))
                #expect(section.title?.lowercased() == raw.lowercased())
                #expect(section.id.hasPrefix(raw + "-"), "section ids keep the provider text")
                for item in section.items {
                    checked += 1
                    let original = try #require(item.rawName ?? (item.name == item.providerName ? item.name : nil))
                    #expect(item.providerName == original)
                    #expect(item.name == DisplayText.normalized(original))
                    #expect(item.name.lowercased() == original.lowercased(), "\(original)")
                    #expect(DisplayText.normalized(item.name) == item.name, "idempotent: \(original)")
                    #expect(item.name != item.name.uppercased() || original.allSatisfy { !$0.isLetter } || DisplayText.keepUppercase.contains(original),
                            "\(original) is still shouting")
                    #expect(item.category == section.title)
                    #expect(item.id.hasPrefix(raw + "-"), "item ids keep the provider text")
                }
            }
        }
        #expect(checked > 400)
    }

    @Test("Nutrislice names and sections are never altered")
    func nutrisliceUnchanged() throws {
        var checked = 0
        for fixture in [Fixture.middlesexWeek, Fixture.elkRapidsThanksgivingWeek, Fixture.salemKeizerWeek] {
            let week = try MenuParser.week(from: Fixture.data(fixture))
            for section in week.days.flatMap(\.sections) {
                #expect(section.rawTitle == nil)
                for item in section.items {
                    checked += 1
                    #expect(item.rawName == nil)
                    #expect(item.name == item.providerName)
                    #expect(item.name == DisplayText.normalized(item.name), "\(item.name)")
                }
            }
        }
        #expect(checked > 20)
    }

    @Test("Favorites, filtering, recipe identity and old cached menus are unaffected")
    func identityIsPreserved() throws {
        let day = try RutgersParser.menu(rutgersFixture("04-lunch-2026-11-10.html"), date: LocalDate(year: 2026, month: 11, day: 10), meal: "Lunch")
        let item = try #require(day.items.first { $0.providerName == "TURKEY & PROVOLONE ON KAISER" })
        #expect(item.name == "Turkey & Provolone on Kaiser")
        // A favorite saved from the old all-caps text still matches the same dish.
        let oldKey = Favorites.normalize("TURKEY & PROVOLONE ON KAISER")
        #expect(Favorites.normalize(item.name) == oldKey)
        #expect(Favorites.matches(in: day, favorites: [oldKey]).map(\.id) == [item.id])
        // The recipe identity and form token never come from the display text.
        #expect(item.foodID.range(of: #"^\d+\*\d+"#, options: .regularExpression) != nil)
        #expect(item.providerReference?.hasPrefix(item.foodID + "*") == true)
        // Filtering is case-insensitive, so the same needles match the same items as against the raw text.
        for needle in ["turkey", "TURKEY", "Provolone", "kaiser", "&", "bbq", "xyz"] {
            for candidate in day.items {
                #expect(candidate.name.localizedCaseInsensitiveContains(needle) == candidate.providerName.localizedCaseInsensitiveContains(needle),
                        "\(candidate.providerName) / \(needle)")
            }
        }
        // A menu cached by the previous build (no rawName / rawTitle keys) still decodes.
        let legacy = Data(#"{"id":"x","foodID":"1*1","name":"OLD ENTRY","allergens":[],"dietaryTags":[],"foodGroups":[],"nutrition":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(MenuItem.self, from: legacy)
        #expect(decoded.name == "OLD ENTRY" && decoded.providerName == "OLD ENTRY")
    }

    @Test("Top-protein ranking: order, tie-breaks and stations come out the same as before")
    func rankingUnchanged() throws {
        func entry(_ id: String, _ raw: String, protein: Double) -> MenuItem {
            let shown = DisplayText.normalized(raw)
            return MenuItem(id: id, foodID: id, name: shown, category: "Lunch Takeout", calories: 200,
                            nutrition: [Nutrient(name: "Protein", amount: protein, unit: "g")], rawName: raw)
        }
        // Raw order: "BBQ..." < "BEEF..." but "Bbq" is not guaranteed to sort the same way as "Bbq" vs "Beef" in
        // display text; the tie-break must use the provider's own string.
        let day = MenuDay(date: LocalDate(year: 2026, month: 11, day: 10), sections: [
            MenuSection(id: "a", title: "Lunch Takeout", items: [
                entry("1", "BEEF STROGANOFF", protein: 20),
                entry("2", "BBQ PULLED PORK", protein: 20),
                entry("3", "ROTISSERIE CHICKEN", protein: 30),
                entry("4", "ZA'ATAR HADDOCK", protein: 20),
            ], rawTitle: "LUNCH TAKEOUT")
        ])
        let top = PickGoal.highProtein.top(in: day, avoiding: [])
        #expect(top.map(\.providerName) == ["ROTISSERIE CHICKEN", "BBQ PULLED PORK", "BEEF STROGANOFF", "ZA'ATAR HADDOCK"])
        #expect(top.map(\.name) == ["Rotisserie Chicken", "BBQ Pulled Pork", "Beef Stroganoff", "Za'atar Haddock"])
        #expect(top.allSatisfy { $0.category == "Lunch Takeout" })
    }
}
