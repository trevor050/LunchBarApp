import AppKit
import LunchKit
import SwiftUI

/// Renders the real popover (with live data) to PNG files without showing any UI.
///
///     LunchBar --render-snapshots <out-dir> <district> <school-slug> <menu-type> <yyyy-mm-dd> [options]
///
/// Options:
///   --steps N        press the next-day arrow N times (negative for previous) before rendering
///   --offline        load once, then lose the network and refresh (stale-copy banner)
///   --offline-cold   no network from the start (offline empty state)
///   --expand TEXT    expand the first item whose name contains TEXT
///   --avoid-milk     flag milk as an avoided allergen
///   --settings       also render the Settings window and the first-run school picker
///   --protein-lean   use protein per 100 calories
///   --filter TEXT    filter the full menu by item name
///   --loading        delay report transport to render the actual pending state
///   --matrix         verify hall/meal/day switching and cached reopens
///
/// Used to produce README images and to check every state in light and dark mode.
@MainActor
enum SnapshotRenderer {
    static func run(arguments: [String]) {
        guard arguments.count >= 5, let day = LocalDate(iso: arguments[4]) else {
            FileHandle.standardError.write(Data("usage: LunchBar --render-snapshots <out-dir> <district> <school> <menu-type> <yyyy-mm-dd>\n".utf8))
            exit(64)
        }
        let output = URL(filePath: arguments[0], directoryHint: .isDirectory)
        let district = arguments[1], schoolSlug = arguments[2], menuSlug = arguments[3]
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let defaultsName = "LunchBarSnapshots-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        let settings = AppSettings(defaults: defaults)
        let network = SwitchableLoader()
        let client = NutrisliceClient(loader: network)
        if arguments.contains("--loading") { network.delayReports = true }

        if district == "rutgers-foodpro" {
            guard let hall = RutgersLocations.foodPro.first(where: { $0.slug == schoolSlug }),
                  let meal = hall.menuTypes.first(where: { $0.slug.caseInsensitiveCompare(menuSlug) == .orderedSame }) else { exit(1) }
            settings.source = RutgersLocations.source(hall: hall, meal: meal)
        } else {
            var schools: [School]?
            var districtName: String?
            Task {
                schools = try? await client.schools(district: district)
                districtName = await client.districtName(district: district)
            }
            spin(until: { schools != nil }, timeout: 20)
            guard let school = schools?.first(where: { $0.slug == schoolSlug }),
                  let type = school.menuTypes.first(where: { $0.slug == menuSlug }) else {
                FileHandle.standardError.write(Data("school or menu type not found\n".utf8))
                exit(1)
            }
            settings.source = MenuSource(district: district, districtName: districtName, school: school, menuType: type)
        }
        if arguments.contains("--protein-lean") { settings.proteinRanking = .per100Calories }
        if arguments.contains("--avoid-milk") { settings.avoidedAllergens = [.milk] }

        let noon = day.date().map { $0.addingTimeInterval(12 * 3600) } ?? Date()
        let repository = MenuRepository(client: client, cache: MenuCache(directory: nil), foodPro: RutgersFoodPro(loader: network, directory: nil))
        let model = MenuViewModel(settings: settings, repository: repository, now: { noon })
        let settle = { spin(until: { model.phase != .loading && !model.isRefreshing && (arguments.contains("--loading") || !model.nutritionLoading) }, timeout: 60) }
        if arguments.contains("--offline-cold") { network.isOffline = true }
        model.popoverWillOpen()
        settle()
        if arguments.contains("--matrix") {
            verifyMatrix(model: model, network: network, client: client, output: output, date: day, settle: settle)
        }
        let coldRequests = network.requestCount
        model.popoverWillOpen()
        settle()
        print("requests cold=\(coldRequests) warm=\(network.requestCount - coldRequests)")
        if let notice = model.nutritionNotice { print("nutritionNotice=\(notice)") }
        if case .menu(let menu) = model.phase {
            print("items=\(menu.items.count) top=" + model.topProteinItems.map { "\($0.name):\($0.protein ?? 0)g/\($0.calories ?? 0)cal [\($0.foodID)]" }.joined(separator: "; "))
        } else { print("phase=\(model.phase)") }
        if let index = arguments.firstIndex(of: "--steps"), arguments.indices.contains(index + 1), let steps = Int(arguments[index + 1]) {
            for _ in 0..<abs(steps) {
                steps > 0 ? model.showNext() : model.showPrevious()
                settle()
            }
        }
        if let index = arguments.firstIndex(of: "--filter"), arguments.indices.contains(index + 1) {
            model.menuFilter = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--expand"), arguments.indices.contains(index + 1),
           case .menu(let menuDay) = model.phase {
            let needle = arguments[index + 1].lowercased()
            model.expandedItemID = menuDay.items.first { $0.name.lowercased().contains(needle) }?.id
        }
        if model.expandedItemID != nil {
            model.loadDetails(model.expandedItemID)
            spin(until: { false }, timeout: 2)
        }
        if arguments.contains("--loading") { model.loadNutrition() }
        if arguments.contains("--offline") {
            network.isOffline = true
            model.refresh()
            settle()
        }

        let popover = PopoverView(model: model, openSettings: {}, quit: {})
            .background(Color(nsColor: .windowBackgroundColor))
        var name = "\(district)-\(schoolSlug)-\(menuSlug)-\(model.day.isoString)"
        if network.isOffline { name += "-offline" }
        render(popover, size: PopoverView.size, appearance: .aqua, to: output.appending(path: "\(name)-light.png"), fitContent: true)
        render(popover, size: PopoverView.size, appearance: .darkAqua, to: output.appending(path: "\(name)-dark.png"), fitContent: true)

        if arguments.contains("--settings") {
            let finder = SchoolFinder(client: client)
            let settingsView = SettingsView(
                settings: settings, finder: finder, loginItem: LoginItem(), hotKeyStatus: HotKeyStatus(),
                onSourceChange: {}, onHotKeyChange: {}, onNotificationsChange: {}, requestNotifications: { false }
            )
            render(settingsView, size: CGSize(width: 460, height: 900), appearance: .aqua, to: output.appending(path: "settings-light.png"))
            finder.input = district == "rutgers-foodpro" ? "rutgers" : district
            finder.search()
            spin(until: { finder.phase != .searching }, timeout: 20)
            let freshDefaultsName = "LunchBarSnapshotsOnboarding-" + UUID().uuidString
            let freshDefaults = UserDefaults(suiteName: freshDefaultsName)!
            freshDefaults.removePersistentDomain(forName: freshDefaultsName)
            let onboarding = SettingsView(
                settings: AppSettings(defaults: freshDefaults), finder: finder, loginItem: LoginItem(), hotKeyStatus: HotKeyStatus(),
                onSourceChange: {}, onHotKeyChange: {}, onNotificationsChange: {}, requestNotifications: { false }
            )
            render(onboarding, size: CGSize(width: 460, height: 640), appearance: .darkAqua, to: output.appending(path: "onboarding-dark.png"))
            freshDefaults.removePersistentDomain(forName: freshDefaultsName)
        }
        defaults.removePersistentDomain(forName: defaultsName)
        exit(0)
    }

    private static func verifyMatrix(model: MenuViewModel, network: SwitchableLoader, client: NutrisliceClient,
                                     output: URL, date: LocalDate, settle: () -> Void) {
        var records: [[String: Any]] = []
        var failures = 0
        for hall in RutgersLocations.foodPro {
            model.select(place: RutgersLocations.source(hall: hall))
            settle()
            for meal in RutgersLocations.meals.filter({ ["Lunch", "Dinner"].contains($0.slug) }) {
                model.select(menuType: meal)
                settle()
                for selectedDate in [date, date.adding(days: 1)] {
                    model.go(to: selectedDate)
                    settle()
                    guard case .menu(let menu) = model.phase, menu.date == selectedDate, !model.nutritionLoading,
                          model.nutritionNotice == nil, !model.topProteinItems.isEmpty else {
                        failures += 1
                        records.append(["hall": hall.name, "meal": meal.name, "date": selectedDate.isoString, "phase": String(describing: model.phase), "nutritionNotice": model.nutritionNotice ?? ""])
                        continue
                    }
                    let before = network.requestCount
                    model.popoverWillOpen(); model.go(to: selectedDate); settle()
                    let warm = network.requestCount - before
                    let top = model.topProteinItems.map { ["name": $0.name, "protein": $0.protein ?? 0, "calories": $0.calories ?? 0, "recipe": $0.foodID, "station": $0.category ?? ""] as [String: Any] }
                    records.append(["hall": hall.name, "meal": meal.name, "date": selectedDate.isoString,
                                    "items": menu.items.count, "stations": menu.sections.count, "warmRequests": warm, "top": top,
                                    "nutritionNotice": model.nutritionNotice ?? ""])
                    let view = PopoverView(model: model, openSettings: {}, quit: {}).background(Color(nsColor: .windowBackgroundColor))
                    render(view, size: PopoverView.size, appearance: .darkAqua,
                           to: output.appending(path: "matrix-\(hall.slug)-\(meal.slug)-\(selectedDate.isoString).png"), fitContent: true)
                }
            }
        }
        var schools: [School]?
        Task { schools = try? await client.schools(district: "middlesex") }
        spin(until: { schools != nil }, timeout: 20)
        if let school = schools?.first(where: { $0.slug == "middlesex-high" }), let meal = school.menuTypes.first(where: { $0.slug == "lunch" }) {
            model.select(place: MenuSource(district: "middlesex", school: school, menuType: meal))
            model.go(to: date); settle()
            if case .menu(let menu) = model.phase {
                records.append(["hall": school.name, "date": date.isoString, "items": menu.items.count, "topCount": model.topProteinItems.count])
                let view = PopoverView(model: model, openSettings: {}, quit: {}).background(Color(nsColor: .windowBackgroundColor))
                render(view, size: PopoverView.size, appearance: .aqua, to: output.appending(path: "matrix-middlesex.png"), fitContent: true)
            } else { failures += 1 }
        } else { failures += 1 }
        let report: [String: Any] = ["records": records, "failures": failures, "requests": network.requestCount, "savedPlaces": model.settings.savedPlaces.map(\.placeKey)]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output.appending(path: "live-matrix.json")) }
        print("matrix failures=\(failures), requests=\(network.requestCount), savedPlaces=\(model.settings.savedPlaces.count)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func render(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL, fitContent: Bool = false) {
        var renderSize = size
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Give AsyncImage a moment to load thumbnails.
        spin(until: { false }, timeout: 3)
        hosting.layoutSubtreeIfNeeded()
        if fitContent {
            renderSize.height = ceil(hosting.fittingSize.height)
            hosting.setFrameSize(renderSize)
            window.setContentSize(renderSize)
            hosting.layoutSubtreeIfNeeded()
        }

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(renderSize.width * scale), pixelsHigh: Int(renderSize.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = renderSize
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print(url.path)
        }
    }

    private static func spin(until done: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

/// Real URLSession, plus a switch that makes every request fail the way a
/// dropped connection does.
private final class SwitchableLoader: HTTPLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var offline = false
    private var count = 0
    private var delay = false
    var delayReports: Bool {
        get { lock.withLock { delay } }
        set { lock.withLock { delay = newValue } }
    }
    var requestCount: Int { lock.withLock { count } }

    var isOffline: Bool {
        get { lock.withLock { offline } }
        set { lock.withLock { offline = newValue } }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { count += 1 }
        if isOffline { throw URLError(.notConnectedToInternet) }
        if delayReports && request.httpMethod == "POST" { try await Task.sleep(for: .seconds(12)) }
        return try await (request.url?.host == "menuportal23.dining.rutgers.edu" ? RutgersFoodPro.defaultSession : NutrisliceClient.defaultSession).data(for: request)
    }
}
