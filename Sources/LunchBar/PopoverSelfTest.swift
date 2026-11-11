import AppKit
import LunchKit

/// Exercises the actual NSStatusItem/NSPopover path without recording the screen.
/// No preferences are written outside its disposable suite.
@MainActor
enum PopoverSelfTest {
    static var enabled: Bool { CommandLine.arguments.contains("--self-test-popover") }
    static var steps: Int {
        guard let i = CommandLine.arguments.firstIndex(of: "--self-test-popover"), CommandLine.arguments.indices.contains(i + 1) else { return 360 }
        return Int(CommandLine.arguments[i + 1]) ?? 360
    }
    static func settings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "LunchBarPopoverSelfTest")!
        defaults.removePersistentDomain(forName: "LunchBarPopoverSelfTest")
        let settings = AppSettings(defaults: defaults)
        let meals = [MenuType(slug: "lunch", name: "Lunch"), MenuType(slug: "breakfast", name: "Breakfast")]
        settings.source = MenuSource(district: "middlesex", school: School(slug: "middlesex-high", name: "Middlesex High", menuTypes: meals), menuType: meals[0])
        settings.skipWeekends = false
        return settings
    }
    static func log(_ record: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), let line = String(data: data, encoding: .utf8) { print(line); fflush(stdout) }
    }
    static func run(delegate: AppDelegate) async {
        delegate.showPopover()
        for _ in 0..<200 {
            if !delegate.model.isRefreshing && delegate.model.phase != .loading { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        for step in 0..<steps {
            switch step % 10 {
            case 0, 1, 2: delegate.model.showPrevious()
            case 3, 4, 5: delegate.model.showNext()
            case 6:
                if case .menu(let day) = delegate.model.phase { delegate.model.expandedItemID = day.items.first?.id }
            case 7: delegate.model.expandedItemID = nil
            case 8:
                if case .menu(let day) = delegate.model.phase, let item = day.items.first { delegate.settings.toggleFavorite(item) }
            default:
                if let source = delegate.settings.source, let next = source.school.menuTypes.first(where: { $0 != source.menuType }) { delegate.model.select(menuType: next) }
            }
            // Let SwiftUI layout and AppKit's show/resize animations settle, without
            // blocking the main run loop. Also validate after each layout boundary.
            for _ in 0..<8 {
                delegate.settlePopoverLayout()
                try? await Task.sleep(for: .milliseconds(35))
                let boundary = delegate.anchorDiagnostic(step: step)
                if boundary["valid"] as? Bool != true {
                    log(boundary); log(["result": "failed during layout", "step": step]); exit(1)
                }
            }
            let result = delegate.anchorDiagnostic(step: step)
            log(result)
            if result["valid"] as? Bool != true { log(["result": "failed", "step": step]); exit(1) }
        }
        log(["result": "passed", "steps": steps, "guardFires": delegate.anchorGuardFires])
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position LunchBarPopoverSelfTest")
        UserDefaults.standard.removePersistentDomain(forName: "LunchBarPopoverSelfTest")
        NSApp.terminate(nil)
    }
}
