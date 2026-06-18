// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniNotch",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MiniNotch",
            dependencies: [],
            path: "Sources/MiniNotch",
            resources: [
                // 品牌图标（simple-icons 单色 SVG，模板渲染着色）
                .process("Resources")
            ]
        )
    ]
)
