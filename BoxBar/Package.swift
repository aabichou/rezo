// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BoxBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BoxBar",
            path: "Sources/BoxBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
