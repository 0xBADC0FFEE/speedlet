// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Speedlet",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "SpeedletCore",
            path: "Sources/SpeedletCore"
        ),
        .executableTarget(
            name: "Speedlet",
            dependencies: ["SpeedletCore"],
            path: "Sources/Speedlet"
        ),
        .testTarget(
            name: "SpeedletCoreTests",
            dependencies: ["SpeedletCore"],
            path: "Tests/SpeedletCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
