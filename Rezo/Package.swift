// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Rezo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Rezo",
            path: "Sources/Rezo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
