// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 动效库：Metal 渲染的发光/流光效果（AI 解析流光、紧急脉冲）
        .package(url: "https://github.com/margox/SwiftGlow.git", from: "0.1.3")
    ],
    targets: [
        .executableTarget(
            name: "MiniNotch",
            dependencies: [
                .product(name: "SwiftGlow", package: "SwiftGlow")
            ],
            path: "Sources/MiniNotch",
            resources: [
                // 品牌图标（simple-icons 单色 SVG，模板渲染着色）
                .process("Resources")
            ]
        )
    ]
)
