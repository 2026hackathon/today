import AppKit
import SwiftUI

// ============================================================
// BrandIcon —— 品牌图标（Jira / GitHub），风格对齐 SF Symbols 单色小图。
// 资源：Resources/*.svg（simple-icons 官方单色矢量），NSImage 模板渲染，
// 颜色由 foregroundStyle/color 参数控制，与现有图标体系一致。
// 资源加载失败时回退到近似的 SF Symbol，不会出空白。
// ============================================================

struct BrandIcon: View {
    enum Brand: String {
        case jira, github

        /// 资源缺失时的 SF Symbol 兜底
        var fallbackSymbol: String {
            switch self {
            case .jira: "briefcase.fill"
            case .github: "arrow.triangle.pull"
            }
        }
    }

    let brand: Brand
    var size: CGFloat = 11
    var color: Color = DS.Colors.text3

    var body: some View {
        Group {
            if let image = Self.cachedImage(for: brand) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: brand.fallbackSymbol)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(color)
    }

    /// 来源 → 品牌（非 jira/github 来源返回 nil，调用方走原有 SF Symbol 逻辑）
    static func brand(for source: TodoSource) -> Brand? {
        switch source {
        case .jira: .jira
        case .github: .github
        default: nil
        }
    }

    // MARK: - 资源缓存（SVG 解码一次，全列表复用；View.body 即主线程）

    @MainActor private static var cache: [Brand: NSImage] = [:]

    @MainActor private static func cachedImage(for brand: Brand) -> NSImage? {
        if let hit = cache[brand] { return hit }
        guard let url = Bundle.module.url(forResource: brand.rawValue, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            NSLog("[BrandIcon] missing resource: \(brand.rawValue).svg")
            return nil
        }
        image.isTemplate = true
        cache[brand] = image
        return image
    }
}
