// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LunchBarApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LunchBarApp", targets: ["LunchBarApp"])
    ],
    targets: [
        .executableTarget(
            name: "LunchBarApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
