// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MiniNotch",
            path: "Sources/MiniNotch"
        )
    ]
)
