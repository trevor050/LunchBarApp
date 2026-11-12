// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LunchBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LunchBar", targets: ["LunchBar"]),
        .library(name: "LunchKit", targets: ["LunchKit"])
    ],
    dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3")],
    targets: [
        // Networking, parsing, caching and date logic. No AppKit or SwiftUI.
        .target(name: "LunchKit", dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")]),
        // The menu bar app itself.
        .executableTarget(
            name: "LunchBar",
            dependencies: ["LunchKit"]
        ),
        .testTarget(name: "LunchBarTests", dependencies: ["LunchBar"]),
        .testTarget(
            name: "LunchKitTests",
            dependencies: ["LunchKit"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
