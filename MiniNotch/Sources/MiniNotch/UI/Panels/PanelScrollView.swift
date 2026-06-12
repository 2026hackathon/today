import SwiftUI

// ============================================================
// PanelScrollView —— 面板统一滚动容器（带自绘滚动条）。
//
// 为什么自绘：系统设置「始终显示滚动条」时，SwiftUI 的
// .scrollIndicators(.hidden) 压不住 legacy 浅色滚动条，
// 白色滚条直接糊在纯黑岛体上。这里用 .never 彻底关掉系统滚条，
// 自绘一根符合 DS 风格的细条：滚动时浮现、停止 0.8s 后淡出
// （macOS overlay 滚条的行为）。
//
// 用法：把 `ScrollView { ... }.scrollIndicators(.hidden)`
// 直接替换为 `PanelScrollView { ... }`。
// ============================================================

struct PanelScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var thumbVisible = false
    @State private var fadeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { container in
            ScrollView {
                content
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: PanelScrollInfoKey.self,
                                value: PanelScrollInfo(
                                    minY: g.frame(in: .named("panelScroll")).minY,
                                    contentHeight: g.size.height
                                )
                            )
                        }
                    )
            }
            .coordinateSpace(name: "panelScroll")
            .scrollIndicators(.never)
            .onPreferenceChange(PanelScrollInfoKey.self) { info in
                // onPreferenceChange 闭包是 @Sendable nonisolated，实际在主线程回调
                MainActor.assumeIsolated {
                    contentHeight = info.contentHeight
                    scrollOffset = -info.minY
                    flashThumb()
                }
            }
            .overlay(alignment: .topTrailing) {
                thumb(containerHeight: container.size.height)
            }
        }
    }

    // MARK: - 自绘滚动条

    @ViewBuilder
    private func thumb(containerHeight: CGFloat) -> some View {
        let overflow = contentHeight - containerHeight
        if overflow > 1, containerHeight > 0 {
            let thumbHeight = max(30, containerHeight * containerHeight / contentHeight)
            let progress = min(max(scrollOffset / overflow, 0), 1)
            let y = progress * (containerHeight - thumbHeight)

            Capsule()
                .fill(DS.Colors.text3) // 白 36%：贴 DS 文字三级灰，黑底上够看清又不抢
                .frame(width: 3, height: thumbHeight)
                .padding(.trailing, 3)
                .offset(y: y)
                .opacity(thumbVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: thumbVisible)
                .allowsHitTesting(false)
        }
    }

    /// 滚动时浮现，停止 0.8s 后淡出
    private func flashThumb() {
        thumbVisible = true
        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            thumbVisible = false
        }
    }
}

// MARK: - 滚动位置上报

private struct PanelScrollInfo: Equatable, Sendable {
    var minY: CGFloat = 0
    var contentHeight: CGFloat = 0
}

private struct PanelScrollInfoKey: PreferenceKey {
    static let defaultValue = PanelScrollInfo()
    static func reduce(value: inout PanelScrollInfo, nextValue: () -> PanelScrollInfo) {
        value = nextValue()
    }
}
