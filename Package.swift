// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipStack",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure model + history logic. No AppKit, so it can be unit tested.
        .target(
            name: "ClipStackCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Everything that touches AppKit, the pasteboard, and the UI.
        .executableTarget(
            name: "ClipStack",
            dependencies: ["ClipStackCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Embed Info.plist into the binary so `swift run` also behaves as a
            // bundle-identified accessory app, not just the packaged .app.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", "Resources/Info.plist",
            ])]
        ),
        .testTarget(
            name: "ClipStackCoreTests",
            dependencies: ["ClipStackCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
