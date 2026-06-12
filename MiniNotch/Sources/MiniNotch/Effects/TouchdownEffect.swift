import SwiftUI

// ============================================================
// Touchdown 任务降落涟漪（effects spec）
//
// 新任务卡片出现时播放：2-3 个同心圆从中心扩散淡出，
// 颜色按来源区分（DS.sourceColor）：截图紫 / Jira 蓝 / 手动绿 / 日历橙 / 微信绿。
//
// 两种用法：
//
// 1) 便捷封装（推荐，NewTaskCard / BatchCard 直接照抄）：
//
//    @State private var ripple: TodoSource? = nil
//
//    cardBody
//        .touchdownRipple(source: $ripple)
//        .onAppear { ripple = draft.source }   // 赋值即播放，播完自动清回 nil
//
// 2) 手动控制：
//
//    TouchdownRipple(color: DS.sourceColor(.jira)) { /* 播放完成回调 */ }
// ============================================================

// MARK: - 涟漪本体

/// 同心圆涟漪：3 个圆环从中心扩散淡出，0.2s 错峰，总时长 ~1s。
/// 播放完成后调 `onFinished`（主线程）。无交互、不吃鼠标事件。
/// 减弱动态效果开启时不播放，直接回调 `onFinished`。
struct TouchdownRipple: View {
    /// 涟漪颜色，传 `DS.sourceColor(source)`
    let color: Color
    /// 播放结束回调（约 1s 后，主线程）
    let onFinished: () -> Void

    @State private var expanded = false

    /// 圆环个数 / 错峰间隔 / 单环扩散时长
    private static let ringCount = 3
    private static let stagger: Double = 0.2
    private static let ringDuration: Double = 0.6
    /// 总时长 = 最后一环 delay + 单环时长 ≈ 1.0s
    private static var totalDuration: Double {
        Double(ringCount - 1) * stagger + ringDuration
    }

    var body: some View {
        ZStack {
            if !MotionPreference.reduceMotion {
                ForEach(0..<Self.ringCount, id: \.self) { index in
                    Circle()
                        .stroke(color.opacity(0.85), lineWidth: 2)
                        .frame(width: 22, height: 22)
                        .scaleEffect(expanded ? 4.5 : 0.4)
                        .opacity(expanded ? 0 : 0.9)
                        .animation(
                            .easeOut(duration: Self.ringDuration)
                                .delay(Double(index) * Self.stagger),
                            value: expanded
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { expanded = true }
        .task {
            // 减弱动态效果：不播动画，立即收尾
            let wait = MotionPreference.reduceMotion ? 0.0 : Self.totalDuration
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

// MARK: - 便捷封装

/// 绑定 `ripple: TodoSource?`：置为非 nil 时在 overlay 中心播放对应来源色涟漪，
/// 播放完毕自动清回 nil（调用方无需手动管理生命周期）。
struct TouchdownModifier: ViewModifier {
    @Binding var ripple: TodoSource?

    func body(content: Content) -> some View {
        content.overlay {
            if let source = ripple {
                TouchdownRipple(color: DS.sourceColor(source)) {
                    ripple = nil
                }
                // source 变化（连续降落不同来源任务）时重新播放
                .id(source)
            }
        }
    }
}

extension View {
    /// Touchdown 涟漪便捷接入：
    ///
    ///   @State private var ripple: TodoSource? = nil
    ///   card.touchdownRipple(source: $ripple)
    ///   // 触发：ripple = .screenshot   （播完自动清回 nil）
    func touchdownRipple(source: Binding<TodoSource?>) -> some View {
        modifier(TouchdownModifier(ripple: source))
    }
}
