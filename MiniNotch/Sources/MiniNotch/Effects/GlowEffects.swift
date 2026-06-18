import AppKit
import SwiftUI

// ============================================================
// 岛体霓虹外溢：NotchShape + 多向 shadow（只向外发光，不盖文字）。
// 辉光层在 IslandRootView ZStack 最底层，与内容完全分离。
// ============================================================

@MainActor
enum MotionPreference {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - 规格

struct NeonShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    let peak: Double
}

struct IslandNeonGlowSpec {
    let shadows: [NeonShadow]
    let rim: [Color]
    let breathSpeed: Double

    static let aiParsing = IslandNeonGlowSpec(
        shadows: [
            NeonShadow(color: Color(red: 0.2, green: 0.4, blue: 1), radius: 18, x: -12, y: 1, peak: 0.75),
            NeonShadow(color: Color(red: 0.82, green: 0.18, blue: 0.55), radius: 16, x: 0, y: -5, peak: 0.5),
            NeonShadow(color: Color(red: 1, green: 0.42, blue: 0.1), radius: 18, x: 12, y: 1, peak: 0.7),
            NeonShadow(color: Color(red: 1, green: 0.3, blue: 0.4), radius: 14, x: 0, y: 11, peak: 0.45),
        ],
        rim: [DS.Colors.accent, Color(red: 0.82, green: 0.18, blue: 0.55), DS.Colors.accentStrong],
        breathSpeed: 0.9
    )

    static let near = IslandNeonGlowSpec(
        shadows: [
            NeonShadow(color: DS.Colors.warning, radius: 12, x: -8, y: 2, peak: 0.4),
            NeonShadow(color: DS.Colors.warning, radius: 10, x: 8, y: 2, peak: 0.32),
        ],
        rim: [DS.Colors.warning.opacity(0.7), DS.Colors.warning],
        breathSpeed: 0.5
    )

    static let warning = IslandNeonGlowSpec(
        shadows: [
            NeonShadow(color: DS.Colors.warning, radius: 16, x: -12, y: 2, peak: 0.7),
            NeonShadow(color: Color(red: 1, green: 0.45, blue: 0.55), radius: 14, x: 0, y: -4, peak: 0.45),
            NeonShadow(color: Color(red: 1, green: 0.55, blue: 0.25), radius: 15, x: 12, y: 2, peak: 0.55),
            NeonShadow(color: DS.Colors.warning, radius: 11, x: 0, y: 10, peak: 0.4),
        ],
        rim: [DS.Colors.warning, Color(red: 1, green: 0.45, blue: 0.55)],
        breathSpeed: 0.8
    )

    /// 纯红/品红/深绯，无橙
    static let urgent = IslandNeonGlowSpec(
        shadows: [
            NeonShadow(color: DS.Colors.priorityHigh, radius: 18, x: -13, y: 2, peak: 0.88),
            NeonShadow(color: Color(red: 0.92, green: 0.12, blue: 0.48), radius: 14, x: 0, y: -5, peak: 0.52),
            NeonShadow(color: Color(red: 0.68, green: 0.06, blue: 0.20), radius: 17, x: 13, y: 2, peak: 0.8),
            NeonShadow(color: DS.Colors.alert, radius: 12, x: 0, y: 11, peak: 0.5),
        ],
        rim: [DS.Colors.priorityHigh, Color(red: 0.92, green: 0.12, blue: 0.48), DS.Colors.alert],
        breathSpeed: 1.0
    )

    static let gold = IslandNeonGlowSpec(
        shadows: [
            NeonShadow(color: DS.Colors.gold, radius: 16, x: -10, y: 2, peak: 0.75),
            NeonShadow(color: Color(red: 1, green: 0.94, blue: 0.55), radius: 14, x: 10, y: 2, peak: 0.65),
        ],
        rim: [DS.Colors.gold, Color(red: 1, green: 0.92, blue: 0.45)],
        breathSpeed: 1.1
    )
}

// MARK: - 渲染（独立底层，与岛体内容同尺寸）

struct IslandNeonGlow: View {
    let cornerRadius: CGFloat
    let spec: IslandNeonGlowSpec

    var body: some View {
        if MotionPreference.reduceMotion {
            staticGlow
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let breath = 0.55 + 0.45 * (sin(t * spec.breathSpeed * .pi * 2) + 1) / 2
                glowBody(breath: breath)
            }
        }
    }

    private var staticGlow: some View {
        glowBody(breath: 1)
    }

    private func glowBody(breath: Double) -> some View {
        let shape = NotchShape(cornerRadius: cornerRadius)
        return ZStack {
            shadowStack(on: shape.fill(Color.white.opacity(0.004)), breath: breath)
            shape
                .stroke(
                    LinearGradient(colors: spec.rim, startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
                .opacity(0.65 * breath)
        }
        .allowsHitTesting(false)
    }

    private func shadowStack<S: View>(on base: S, breath: Double) -> some View {
        spec.shadows.reduce(AnyView(base)) { view, shadow in
            AnyView(
                view.shadow(
                    color: shadow.color.opacity(shadow.peak * breath),
                    radius: shadow.radius,
                    x: shadow.x,
                    y: shadow.y
                )
            )
        }
    }
}

// MARK: - 公开 API（IslandRootView 用 ZStack 底层挂载，不再 modifier 链叠加）

extension IslandNeonGlowSpec {
    @MainActor
    static func active(
        effectsEnabled: Bool,
        islandState: IslandState,
        overdueTodosEmpty: Bool,
        debugForceRedGlow: Bool,
        goldFlashing: Bool
    ) -> IslandNeonGlowSpec? {
        guard effectsEnabled else { return nil }
        if goldFlashing { return .gold }
        switch islandState {
        case .aiWorking: return .aiParsing
        case .near: return .near
        case .urgent where overdueTodosEmpty && !debugForceRedGlow: return .warning
        case .urgent: return .urgent
        default: return nil
        }
    }
}

struct GoldFlashModifier: ViewModifier {
    let trigger: Int
    @Binding var goldFlashing: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, _ in
                goldFlashing = true
            }
            .task(id: trigger) {
                guard goldFlashing else { return }
                try? await Task.sleep(for: .seconds(1.0))
                guard !Task.isCancelled else { return }
                goldFlashing = false
            }
    }
}
