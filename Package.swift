// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Speedlet",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Speedlet",
            path: "Sources/Speedlet"
        ),
    ],
    swiftLanguageModes: [.v5]
)
