// swift-tools-version: 6.0
import PackageDescription

// AI Meter is a native macOS app, but the data layer is built as a Swift package so
// that Core/provider logic compiles and tests without Xcode, and so that the future
// app, widget and helper targets all consume one normalized library.
let package = Package(
    name: "AIMeter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AIMeterCore", targets: ["AIMeterCore"]),
        .library(name: "AIMeterProviders", targets: ["AIMeterProviders"]),
        .executable(name: "aimeter-claude-bridge", targets: ["AIMeterClaudeBridge"]),
        .executable(name: "aimeter-spike", targets: ["AIMeterSpike"]),
    ],
    targets: [
        .target(
            name: "AIMeterCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "AIMeterProviders",
            dependencies: ["AIMeterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AIMeterClaudeBridge",
            dependencies: ["AIMeterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "AIMeterSpike",
            dependencies: ["AIMeterCore", "AIMeterProviders"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AIMeterCoreTests",
            dependencies: ["AIMeterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AIMeterProvidersTests",
            dependencies: ["AIMeterProviders"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
