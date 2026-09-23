// swift-tools-version: 6.0
import PackageDescription

// v5 language mode, same reasoning as matchnotch: strict concurrency buys
// nothing for a single @MainActor UI app and costs a wall of annotations on
// AppKit and Core Audio types.
let mode: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "NotchPlayer",
    // 15, not 14.4: the machine is 15.7.7 and picking 15 removes every
    // @available annotation the Core Audio process tap would otherwise need.
    platforms: [.macOS(.v15)],
    targets: [
        // Everything testable lives here; the executable is just a launcher.
        .target(name: "NotchPlayerCore", path: "Sources/NotchPlayerCore", swiftSettings: mode),
        .executableTarget(name: "NotchPlayer", dependencies: ["NotchPlayerCore"],
                          path: "Sources/NotchPlayer", swiftSettings: mode),
        .testTarget(name: "NotchPlayerTests", dependencies: ["NotchPlayerCore"],
                    path: "Tests/NotchPlayerTests",
                    resources: [.copy("Fixtures")], swiftSettings: mode),
    ]
)
