import SwiftUI
import AppKit
import Carbon
import Combine

@main
struct LunchBarApp {
    static func main() {
        do {
            let config = try AppConfig.load()
            let app = NSApplication.shared
            let delegate = AppDelegate(config: config)
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        } catch {
            runConfigAlert(error: error)
            exit(1)
        }
    }

    @MainActor
    private static func runConfigAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "LunchBarApp"
        alert.informativeText = "Unable to load configuration. Create a .env file containing NUTRISLICE_ORIGIN, NUTRISLICE_SCHOOL_SLUG, and NUTRISLICE_MENU_TYPE. See README for details.\n\nError: \(error.localizedDescription)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let viewModel: LunchViewModel
    private var hotKey: HotKeyManager?
    private var cancellables = Set<AnyCancellable>()

    init(config: AppConfig) {
        self.viewModel = LunchViewModel(config: config)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpPopover()
        registerGlobalHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
    }

    // Removed dynamic popover resizing to avoid AppKit re-anchoring glitches.

    private func setUpStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "fork.knife", accessibilityDescription: "Lunch Menu")
        statusItem.button?.action = #selector(togglePopover(_:))
        statusItem.button?.target = self
        // Ensure the button actually fires on mouse up even if default settings differ
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.appearsDisabled = false
        self.statusItem = statusItem
    }

    private func setUpPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: LunchViewModel.popoverWidth, height: LunchViewModel.fixedPopoverHeight)
        popover.contentViewController = NSHostingController(rootView: LunchMenuView(viewModel: viewModel))
    }

    private func registerGlobalHotKey() {
        guard hotKey == nil else { return }
        let hotKey = HotKeyManager(keyCode: UInt32(kVK_ANSI_L), modifiers: [UInt32(cmdKey), UInt32(shiftKey)]) { [weak self] in
            DispatchQueue.main.async {
                guard let self, let button = self.statusItem?.button else { return }
                if self.popover.isShown {
                    self.popover.performClose(nil)
                } else {
                    self.showPopover(for: button)
                }
            }
        }
        hotKey.register()
        self.hotKey = hotKey
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(for: button)
        }
    }

    private func showPopover(for button: NSStatusBarButton) {
        viewModel.ensureCurrentDay()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        // Store the anchor rect so subsequent size changes keep the same attachment point.
        popover.positioningRect = button.bounds
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI Content

struct LunchMenuView: View {
    @ObservedObject var viewModel: LunchViewModel
    @State private var expandedItemID: Int?

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(width: LunchViewModel.popoverWidth, height: LunchViewModel.fixedPopoverHeight)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit LunchBarApp")

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(viewModel.displayedDate.formatted(.dateTime.month(.abbreviated).day()))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                controlButton(icon: "chevron.left", help: "Previous day") {
                    viewModel.loadPrevious()
                }
                controlButton(icon: "arrow.clockwise", help: "Refresh") {
                    viewModel.refresh()
                }
                controlButton(icon: "chevron.right", help: "Next day") {
                    viewModel.loadNext()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if let error = viewModel.errorMessage {
            Text(error)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.items) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    expandedItemID = expandedItemID == item.id ? nil : item.id
                                }
                            } label: {
                                LunchRow(item: item, isExpanded: expandedItemID == item.id)
                            }
                            .buttonStyle(.plain)

                            if expandedItemID == item.id {
                                NutritionDetailView(item: item)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
                // Smooth the expand/collapse of the nutrition card
                .animation(.easeInOut(duration: 0.18), value: expandedItemID)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.hidden)
        }
    }

    private func controlButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct LunchRow: View {
    let item: LunchFood
    var isExpanded: Bool = false
    private let imageSize: CGFloat = 50

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageURL = item.imageURL {
                AsyncImage(url: imageURL, transaction: Transaction(animation: .default)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: imageSize, height: imageSize)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                            .frame(width: imageSize, height: imageSize)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.gray.opacity(0.1))
            .frame(width: imageSize, height: imageSize)
            .overlay(Image(systemName: "fork.knife").foregroundStyle(.gray))
    }
}

struct NutritionDetailView: View {
    let item: LunchFood

    private var allergens: [String] {
        item.icons?.foodIcons?.compactMap { $0.name } ?? []
    }

    private var categories: [String] {
        item.icons?.myplateIcons?.compactMap { $0.name } ?? []
    }

    private var nutritionEntries: [(title: String, value: String)] {
        var entries: [(String, String)] = []
        if let calories = item.roundedNutritionInfo?.calories {
            entries.append(("Calories", "\(Int(calories.rounded()))"))
        }
        func append(_ title: String, _ value: Double?, unit: String) {
            guard let value else { return }
            let formatted = value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(value))
                : String(format: "%.1f", value)
            entries.append((title, "\(formatted)\(unit)"))
        }
        append("Total Fat", item.roundedNutritionInfo?.gFat, unit: "g")
        append("Saturated Fat", item.roundedNutritionInfo?.gSaturatedFat, unit: "g")
        append("Trans Fat", item.roundedNutritionInfo?.gTransFat, unit: "g")
        append("Cholesterol", item.roundedNutritionInfo?.mgCholesterol, unit: "mg")
        append("Sodium", item.roundedNutritionInfo?.mgSodium, unit: "mg")
        append("Total Carbohydrate", item.roundedNutritionInfo?.gCarbs, unit: "g")
        append("Dietary Fiber", item.roundedNutritionInfo?.gFiber, unit: "g")
        append("Total Sugars", item.roundedNutritionInfo?.gSugar, unit: "g")
        append("Added Sugars", item.roundedNutritionInfo?.gAddedSugar, unit: "g")
        append("Protein", item.roundedNutritionInfo?.gProtein, unit: "g")
        append("Calcium", item.roundedNutritionInfo?.mgCalcium, unit: "mg")
        append("Iron", item.roundedNutritionInfo?.mgIron, unit: "mg")
        append("Potassium", item.roundedNutritionInfo?.mgPotassium, unit: "mg")
        append("Vitamin D", item.roundedNutritionInfo?.mgVitaminD, unit: "mcg")
        append("Vitamin C", item.roundedNutritionInfo?.mgVitaminC, unit: "mg")
        return entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if !allergens.isEmpty {
                TagSection(title: "Allergens", tags: allergens)
            }
            if !categories.isEmpty {
                TagSection(title: "Meal Components", tags: categories)
            }
            if let ingredients = item.ingredients, !ingredients.isEmpty {
                SectionHeader("Ingredients")
                Text(ingredients)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            nutritionSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            if let imageURL = item.imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.1)
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.title3.weight(.semibold))
                if let highlight = item.foodHighlightMessage, !highlight.isEmpty {
                    Text(highlight)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let serving = item.servingSizeInfo?.formatted {
                    Label("Serving Size: \(serving)", systemImage: "scalemass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Nutrition Facts")
            if nutritionEntries.isEmpty {
                Text("No nutrition details available.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(nutritionEntries.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.title)
                                .font(.body)
                            Spacer()
                            Text(entry.value)
                                .font(.body.weight(.semibold))
                        }
                        Divider()
                    }
                }
            }
            Text("The % Daily Value (DV) tells you how much a nutrient in a serving contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .textCase(nil)
    }
}

struct TagSection: View {
    let title: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - View Model & Models
// MARK: - View Model & Models

@MainActor
final class LunchViewModel: ObservableObject {
    static let popoverWidth: CGFloat = 320
    static let fixedPopoverHeight: CGFloat = 320
    private static let minHeight: CGFloat = 240
    private static let maxHeight: CGFloat = 400
    private static let baseHeight: CGFloat = 160
    private static let rowHeight: CGFloat = 72

    @Published private(set) var displayedDate: Date
    @Published private(set) var items: [LunchFood] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var preferredHeight: CGFloat = LunchViewModel.height(for: 0)

    private let calendar = Calendar(identifier: .gregorian)
    private let urlSession: URLSession
    private let config: AppConfig

    // Weekend messages pool
    private let weekendMessages: [String] = [
        "Enjoy the weekend! No lunch today.",
        "Happy weekend! The cafeteria is taking a break.",
        "Rest up! No school lunch on weekends.",
        "No lunch today! Enjoy your weekend.",
        "No lunch posted—just sunshine and free time!"
    ]
    private func randomWeekendMessage() -> String { weekendMessages.randomElement() ?? weekendMessages.first! }

    private func messageForNoLunch(on date: Date, weekdayFallback: String) -> String {
        if let holidayGreeting = holidayMessage(for: date) {
            return holidayGreeting
        }
        return calendar.isDateInWeekend(date) ? randomWeekendMessage() : weekdayFallback
    }

    private func holidayMessage(for date: Date) -> String? {
        guard let year = calendar.dateComponents([.year], from: date).year else { return nil }

        let easterSunday = easterDate(forYear: year)
        let goodFriday = easterSunday.flatMap { calendar.date(byAdding: .day, value: -2, to: $0) }
        let easterMonday = easterSunday.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }

        let thanksgiving = nthWeekday(5, ordinal: 4, month: 11, year: year)
        let thanksgivingEve = thanksgiving.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
        let dayAfterThanksgiving = thanksgiving.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }

        let memorialDay = lastWeekday(2, month: 5, year: year)
        let laborDay = nthWeekday(2, ordinal: 1, month: 9, year: year)
        let indigenousPeoplesDay = nthWeekday(2, ordinal: 2, month: 10, year: year)
        let patriotsDay = nthWeekday(2, ordinal: 3, month: 4, year: year)
        let electionDay = electionDay(forYear: year)

        let roshHashanah = hebrewHoliday(month: 1, day: 1, gregorianYear: year, occursInAutumn: true)
        let yomKippur = hebrewHoliday(month: 1, day: 10, gregorianYear: year, occursInAutumn: true)
        let passover = hebrewHoliday(month: 8, day: 15, gregorianYear: year, occursInAutumn: false)
        let hanukkah = hebrewHoliday(month: 3, day: 25, gregorianYear: year, occursInAutumn: true)

        let ramadanStart = islamicHoliday(month: 9, day: 1, gregorianYear: year)
        let eidAlFitr = islamicHoliday(month: 10, day: 1, gregorianYear: year)
        let eidAlAdha = islamicHoliday(month: 12, day: 10, gregorianYear: year)

        let lunarNewYear = lunarNewYearDate(for: year)
        let diwali = diwaliDate(for: year)

        let orthodoxChristmas = fixedDate(month: 1, day: 7, year: year)

        let matches: [(Date?, String)] = [
            (fixedDate(month: 1, day: 1, year: year), "Happy New Year's Day! Enjoy the break."),
            (observedDate(month: 1, day: 1, year: year), "New Year's Day observed—enjoy the extended holiday!"),
            (orthodoxChristmas, "Merry Orthodox Christmas!"),
            (nthWeekday(2, ordinal: 3, month: 1, year: year), "Honoring Dr. King today. Happy Martin Luther King Jr. Day!"),
            (nthWeekday(2, ordinal: 3, month: 2, year: year), "Happy Presidents Day! School's out today."),
            (lunarNewYear, "Happy Lunar New Year!"),
            (patriotsDay, "Happy Patriots' Day! Enjoy the day off."),
            (passover, "Chag Pesach Sameach! Enjoy Passover break."),
            (roshHashanah, "Shanah Tovah! Happy Rosh Hashanah."),
            (yomKippur, "Yom Kippur observance today—have an easy fast."),
            (hanukkah, "Happy Hanukkah! Enjoy the Festival of Lights."),
            (ramadanStart, "Ramadan Mubarak!"),
            (eidAlFitr, "Eid al-Fitr Mubarak!"),
            (eidAlAdha, "Eid al-Adha Mubarak!"),
            (goodFriday, "Good Friday break—enjoy the long weekend!"),
            (easterMonday, "Happy Easter Monday! See you back at school soon."),
            (memorialDay, "Remember and honor—Happy Memorial Day!"),
            (fixedDate(month: 6, day: 19, year: year), "Happy Juneteenth! Celebrate freedom today."),
            (observedDate(month: 6, day: 19, year: year), "Juneteenth observed—enjoy the day off!"),
            (fixedDate(month: 7, day: 4, year: year), "Happy Independence Day!"),
            (observedDate(month: 7, day: 4, year: year), "Independence Day observed—enjoy the celebration!"),
            (laborDay, "Happy Labor Day! Enjoy the extra rest."),
            (indigenousPeoplesDay, "Indigenous Peoples' Day—school's out today."),
            (diwali, "Happy Diwali! Enjoy the festival of lights."),
            (fixedDate(month: 11, day: 11, year: year), "Honoring our heroes this Veterans Day."),
            (observedDate(month: 11, day: 11, year: year), "Veterans Day observed—thank you to all who served."),
            (electionDay, "Election Day—schools are closed today."),
            (thanksgivingEve, "Happy Thanksgiving break! Safe travels."),
            (thanksgiving, "Happy Thanksgiving! Enjoy the feast."),
            (dayAfterThanksgiving, "Enjoy the rest of Thanksgiving break!"),
            (fixedDate(month: 12, day: 24, year: year), "Merry Christmas Eve!"),
            (fixedDate(month: 12, day: 25, year: year), "Merry Christmas!"),
            (observedDate(month: 12, day: 25, year: year), "Christmas Day observed—enjoy the holiday!"),
            (fixedDate(month: 12, day: 26, year: year), "Winter break is in full swing—see you soon!"),
            (fixedDate(month: 12, day: 27, year: year), "Winter break continues. Stay cozy!"),
            (fixedDate(month: 12, day: 28, year: year), "Winter break vibes only today."),
            (fixedDate(month: 12, day: 29, year: year), "Still on winter break—enjoy the downtime!"),
            (fixedDate(month: 12, day: 30, year: year), "Winter break is almost over—make it count!"),
            (fixedDate(month: 12, day: 31, year: year), "Happy New Year's Eve! See you next year."),
        ]

        for (candidate, message) in matches {
            if let candidate, calendar.isDate(date, inSameDayAs: candidate) {
                return message
            }
        }
        return nil
    }

    private func fixedDate(month: Int, day: Int, year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func observedDate(month: Int, day: Int, year: Int) -> Date? {
        guard let actual = fixedDate(month: month, day: day, year: year) else { return nil }
        let weekday = calendar.component(.weekday, from: actual)
        switch weekday {
        case 7:
            return calendar.date(byAdding: .day, value: -1, to: actual)
        case 1:
            return calendar.date(byAdding: .day, value: 1, to: actual)
        default:
            return nil
        }
    }

    private func nthWeekday(_ weekday: Int, ordinal: Int, month: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.weekday = weekday
        components.weekdayOrdinal = ordinal
        return calendar.date(from: components)
    }

    private func lastWeekday(_ weekday: Int, month: Int, year: Int) -> Date? {
        guard let firstDay = fixedDate(month: month, day: 1, year: year),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return nil }
        for day in range.reversed() {
            if let candidate = fixedDate(month: month, day: day, year: year),
               calendar.component(.weekday, from: candidate) == weekday {
                return candidate
            }
        }
        return nil
    }

    private func electionDay(forYear year: Int) -> Date? {
        guard let firstMonday = nthWeekday(2, ordinal: 1, month: 11, year: year) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: firstMonday)
    }

    private func easterDate(forYear year: Int) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return fixedDate(month: month, day: day, year: year)
    }

    private func hebrewHoliday(month: Int, day: Int, gregorianYear: Int, occursInAutumn: Bool) -> Date? {
        let hebrewCalendar = Calendar(identifier: .hebrew)
        let hebrewYear = gregorianYear + (occursInAutumn ? 3761 : 3760)

        var components = DateComponents()
        components.calendar = hebrewCalendar
        components.year = hebrewYear
        components.month = month
        components.day = day

        guard let date = hebrewCalendar.date(from: components) else { return nil }
        let normalized = calendar.startOfDay(for: date)
        return calendar.component(.year, from: normalized) == gregorianYear ? normalized : nil
    }

    private func islamicHoliday(month: Int, day: Int, gregorianYear: Int) -> Date? {
        let islamicCalendar = Calendar(identifier: .islamicUmmAlQura)
        let baseYear = gregorianYear - 579

        for delta in -1...1 {
            var components = DateComponents()
            components.calendar = islamicCalendar
            components.year = baseYear + delta
            components.month = month
            components.day = day

            guard let date = islamicCalendar.date(from: components) else { continue }
            let normalized = calendar.startOfDay(for: date)
            if calendar.component(.year, from: normalized) == gregorianYear {
                return normalized
            }
        }

        return nil
    }

    private func lunarNewYearDate(for year: Int) -> Date? {
        let knownDates: [Int: (Int, Int)] = [
            2023: (1, 22),
            2024: (2, 10),
            2025: (1, 29),
            2026: (2, 17),
            2027: (2, 6),
            2028: (1, 26),
            2029: (2, 13),
            2030: (2, 3)
        ]
        guard let (month, day) = knownDates[year] else { return nil }
        return fixedDate(month: month, day: day, year: year)
    }

    private func diwaliDate(for year: Int) -> Date? {
        let knownDates: [Int: (Int, Int)] = [
            2023: (11, 12),
            2024: (11, 1),
            2025: (10, 20),
            2026: (11, 8),
            2027: (10, 29),
            2028: (10, 17),
            2029: (11, 5),
            2030: (10, 26)
        ]
        guard let (month, day) = knownDates[year] else { return nil }
        return fixedDate(month: month, day: day, year: year)
    }

    init(config: AppConfig, date: Date = Date()) {
        self.config = config
        self.displayedDate = date.startOfDay(in: calendar)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        self.urlSession = URLSession(configuration: configuration)

        refresh()
    }

    func ensureCurrentDay() {
        let today = Date().startOfDay(in: calendar)
        if displayedDate != today {
            displayedDate = today
            refresh()
        }
    }

    func refresh() {
        Task { await fetch(for: displayedDate) }
    }

    func loadPrevious() {
        displayedDate = calendar.date(byAdding: .day, value: -1, to: displayedDate) ?? displayedDate
        refresh()
    }

    func loadNext() {
        displayedDate = calendar.date(byAdding: .day, value: 1, to: displayedDate) ?? displayedDate
        refresh()
    }

    private static func height(for itemCount: Int) -> CGFloat {
        let dynamic = baseHeight + (CGFloat(itemCount) * rowHeight)
        return min(max(dynamic, minHeight), maxHeight)
    }

    private func fetch(for date: Date) async {
        isLoading = true
        errorMessage = nil
        items = []
        preferredHeight = Self.height(for: 0)

        let isWeekend = calendar.isDateInWeekend(date)

        do {
            let parts = DateParts(date: date, calendar: calendar)
            let endpoint = config.apiOrigin
                .appendingPathComponent("menu")
                .appendingPathComponent("api")
                .appendingPathComponent("weeks")
                .appendingPathComponent("school")
                .appendingPathComponent(config.schoolSlug)
                .appendingPathComponent("menu-type")
                .appendingPathComponent(config.menuTypeSlug)
                .appendingPathComponent(parts.pathComponent)

            var request = URLRequest(url: endpoint)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("watforlunch-menubar/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LunchError.invalidResponse
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                throw LunchError.server(status: httpResponse.statusCode, body: String(snippet))
            }

            let decoded = try JSONDecoder().decode(WeekMenuResponse.self, from: data)
            if let day = decoded.days.first(where: { $0.dateString == parts.isoString }) {
                let foods = day.menuItems
                    .filter { !$0.isSectionTitle }
                    .compactMap { $0.food }

                if foods.isEmpty {
                    errorMessage = messageForNoLunch(on: date, weekdayFallback: "No lunch posted yet.")
                    preferredHeight = Self.height(for: 0)
                } else {
                    items = foods
                    preferredHeight = Self.height(for: foods.count)
                }
            } else {
                errorMessage = messageForNoLunch(on: date, weekdayFallback: "No menu for this date.")
                preferredHeight = Self.height(for: 0)
            }
        } catch let error as LunchError {
            errorMessage = isWeekend ? randomWeekendMessage() : error.description
            preferredHeight = Self.height(for: 0)
        } catch {
            errorMessage = isWeekend ? randomWeekendMessage() : error.localizedDescription
            preferredHeight = Self.height(for: 0)
        }

        isLoading = false
    }
}

struct WeekMenuResponse: Decodable {
    let days: [MenuDay]

    struct MenuDay: Decodable {
        let date: String
        let menu_items: [MenuItem]

        var dateString: String { date }
        var menuItems: [MenuItem] { menu_items }
    }

    struct MenuItem: Decodable {
        let is_section_title: Bool
        let food: LunchFood?

        var isSectionTitle: Bool { is_section_title }
    }
}

struct LunchFood: Decodable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let image_url: URL?
    let ingredients: String?
    let food_highlight_message: String?
    let serving_size_info: ServingSizeInfo?
    let rounded_nutrition_info: RoundedNutritionInfo?
    let icons: FoodIcons?

    var imageURL: URL? { image_url }
    var foodHighlightMessage: String? { food_highlight_message }
    var servingSizeInfo: ServingSizeInfo? { serving_size_info }
    var roundedNutritionInfo: RoundedNutritionInfo? { rounded_nutrition_info }
}

struct ServingSizeInfo: Decodable {
    let serving_size_amount: String?
    let serving_size_unit: String?

    var formatted: String? {
        switch (serving_size_amount, serving_size_unit) {
        case let (amount?, unit?) where !amount.isEmpty && !unit.isEmpty:
            return "\(amount) \(unit)"
        case let (amount?, nil) where !amount.isEmpty:
            return amount
        default:
            return nil
        }
    }
}

struct RoundedNutritionInfo: Decodable {
    let calories: Double?
    let gFat: Double?
    let gSaturatedFat: Double?
    let gTransFat: Double?
    let mgCholesterol: Double?
    let gCarbs: Double?
    let gFiber: Double?
    let gSugar: Double?
    let gAddedSugar: Double?
    let gProtein: Double?
    let mgSodium: Double?
    let mgPotassium: Double?
    let mgCalcium: Double?
    let mgIron: Double?
    let mgVitaminC: Double?
    let mgVitaminD: Double?

    enum CodingKeys: String, CodingKey {
        case calories
        case gFat = "g_fat"
        case gSaturatedFat = "g_saturated_fat"
        case gTransFat = "g_trans_fat"
        case mgCholesterol = "mg_cholesterol"
        case gCarbs = "g_carbs"
        case gFiber = "g_fiber"
        case gSugar = "g_sugar"
        case gAddedSugar = "g_added_sugar"
        case gProtein = "g_protein"
        case mgSodium = "mg_sodium"
        case mgPotassium = "mg_potassium"
        case mgCalcium = "mg_calcium"
        case mgIron = "mg_iron"
        case mgVitaminC = "mg_vitamin_c"
        case mgVitaminD = "mg_vitamin_d"
    }
}

struct FoodIcons: Decodable {
    let food_icons: [FoodIcon]?
    let myplate_icons: [FoodIcon]?

    var foodIcons: [FoodIcon]? { food_icons }
    var myplateIcons: [FoodIcon]? { myplate_icons }
}

struct FoodIcon: Decodable, Hashable {
    let name: String?
}

enum LunchError: LocalizedError {
    case invalidResponse
    case server(status: Int, body: String)

    var description: String {
        switch self {
        case .invalidResponse:
            return "Invalid response"
        case .server(let status, let body):
            return "Server error (\(status)): \(body)"
        }
    }

    var errorDescription: String? { description }
}

struct DateParts {
    let isoString: String
    let pathComponent: String

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        let monthString = String(format: "%02d", month)
        let dayString = String(format: "%02d", day)
        isoString = String(format: "%04d-%@-%@", year, monthString, dayString)
        pathComponent = "\(year)/\(monthString)/\(dayString)"
    }
}

private extension Date {
    func startOfDay(in calendar: Calendar) -> Date {
        calendar.startOfDay(for: self)
    }
}
