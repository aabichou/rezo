// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rezo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Rezo",
            path: "Sources/Rezo"
        )
    ]
)
