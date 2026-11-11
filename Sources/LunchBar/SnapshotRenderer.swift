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

        let defaults = UserDefaults(suiteName: "LunchBarSnapshots")!
        defaults.removePersistentDomain(forName: "LunchBarSnapshots")
        let settings = AppSettings(defaults: defaults)
        let network = SwitchableLoader()
        let client = NutrisliceClient(loader: network)

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
        if arguments.contains("--avoid-milk") { settings.avoidedAllergens = [.milk] }

        let noon = day.date().map { $0.addingTimeInterval(12 * 3600) } ?? Date()
        let repository = MenuRepository(client: client, cache: MenuCache(directory: nil))
        let model = MenuViewModel(settings: settings, repository: repository, now: { noon })
        let settle = { spin(until: { model.phase != .loading && !model.isRefreshing }, timeout: 20) }
        if arguments.contains("--offline-cold") { network.isOffline = true }
        model.popoverWillOpen()
        settle()
        if let index = arguments.firstIndex(of: "--steps"), arguments.indices.contains(index + 1), let steps = Int(arguments[index + 1]) {
            for _ in 0..<abs(steps) {
                steps > 0 ? model.showNext() : model.showPrevious()
                settle()
            }
        }
        if let index = arguments.firstIndex(of: "--expand"), arguments.indices.contains(index + 1),
           case .menu(let menuDay) = model.phase {
            let needle = arguments[index + 1].lowercased()
            model.expandedItemID = menuDay.items.first { $0.name.lowercased().contains(needle) }?.id
        }
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
            finder.input = district
            finder.search()
            spin(until: { finder.phase != .searching }, timeout: 20)
            let freshDefaults = UserDefaults(suiteName: "LunchBarSnapshotsOnboarding")!
            freshDefaults.removePersistentDomain(forName: "LunchBarSnapshotsOnboarding")
            let onboarding = SettingsView(
                settings: AppSettings(defaults: freshDefaults), finder: finder, loginItem: LoginItem(), hotKeyStatus: HotKeyStatus(),
                onSourceChange: {}, onHotKeyChange: {}, onNotificationsChange: {}, requestNotifications: { false }
            )
            render(onboarding, size: CGSize(width: 460, height: 640), appearance: .darkAqua, to: output.appending(path: "onboarding-dark.png"))
            freshDefaults.removePersistentDomain(forName: "LunchBarSnapshotsOnboarding")
        }
        defaults.removePersistentDomain(forName: "LunchBarSnapshots")
        exit(0)
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

    var isOffline: Bool {
        get { lock.withLock { offline } }
        set { lock.withLock { offline = newValue } }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if isOffline { throw URLError(.notConnectedToInternet) }
        return try await NutrisliceClient.defaultSession.data(for: request)
    }
}
