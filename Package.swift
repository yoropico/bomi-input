// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Bomi",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BomiEngine"),
        .testTarget(name: "BomiEngineTests", dependencies: ["BomiEngine"]),
        // Pure, IMK-free app logic (key translation, language state, prefs,
        // toggle gate). Split out from the executable so `swift test` can cover
        // it — an executableTarget with a top-level `main` can't be @testable.
        .target(name: "BomiCore"),
        .testTarget(name: "BomiCoreTests", dependencies: ["BomiCore"]),
        .executableTarget(
            name: "Bomi",
            dependencies: ["BomiEngine", "BomiCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
