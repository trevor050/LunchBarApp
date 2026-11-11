import AppKit

@main
@MainActor
enum LunchBarApp {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-snapshots") {
            SnapshotRenderer.run(arguments: Array(arguments.dropFirst(index + 1)))
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
