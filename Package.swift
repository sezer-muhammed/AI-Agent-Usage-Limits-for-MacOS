// swift-tools-version: 6.0
import Foundation
import PackageDescription

// AI Meter is a native macOS app, but the data layer is built as a Swift package so
// that Core/provider logic compiles and tests without Xcode, and so that the future
// app, widget and helper targets all consume one normalized library.
// Swift Testing's macro plugin ships inside the toolchain, but when only the
// Command Line Tools are installed it is not on the default plugin search path,
// so `swift test` fails to build the test targets. Point the compiler at the
// plugin that belongs to the active toolchain.
//
// This resolves to nothing once Xcode is installed — Xcode finds its own plugin,
// and mixing a plugin from one toolchain into another is exactly what must not
// happen. It also means the package carries no unsafe flags in that case, so it
// stays usable as a dependency of the future app target.
let testPluginSettings: [SwiftSetting] = {
    let commandLineTools = "/Library/Developer/CommandLineTools"
    let pluginPath = "\(commandLineTools)/usr/lib/swift/host/plugins/testing"

    let fileManager = FileManager.default
    let xcodeInstalled = fileManager.fileExists(atPath: "/Applications/Xcode.app")
    guard !xcodeInstalled, fileManager.fileExists(atPath: pluginPath) else { return [] }

    return [.unsafeFlags(["-plugin-path", pluginPath])]
}()

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
            dependencies: ["AIMeterCore", "AIMeterProviders"],
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
            swiftSettings: [.swiftLanguageMode(.v6)] + testPluginSettings
        ),
        .testTarget(
            name: "AIMeterProvidersTests",
            dependencies: ["AIMeterProviders"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)] + testPluginSettings
        ),
    ]
)
