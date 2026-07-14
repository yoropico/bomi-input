// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Bomi",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BomiEngine"),
        .testTarget(name: "BomiEngineTests", dependencies: ["BomiEngine"]),
        .executableTarget(
            name: "Bomi",
            dependencies: ["BomiEngine"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
