import AppKit
import SwiftUI

// ============================================================
// Glow 动效封装（effects spec）—— 给岛体形状用的 View 扩展。
//
// 自绘实现（不依赖第三方 Metal 库）：glow = 沿岛体轮廓描边 + 高斯模糊的光晕，
// 紧贴 NotchShape 外缘，向外扩散有限（≈ blur 半径），不会像旧方案那样在岛体
// 下方铺开一大片雾，盖住/干扰下方应用的标签栏与按钮。
//
// 用法（集成层直接照抄）：
//
//   islandShape
//       .aiParsingGlow(active: store.islandState == .aiWorking,
//                      cornerRadius: geometry.cornerRadius)
//       .urgentGlow(active: store.islandState == .urgent,
//                   cornerRadius: geometry.cornerRadius)
//       .goldFlash(trigger: store.completionFlashCount,   // 每完成一个 todo +1
//                  cornerRadius: geometry.cornerRadius)
//
// 性能契约：active == false / 未触发时直接返回原视图，不挂动画层。
// 可访问性：系统「减弱动态效果」开启时，呼吸/脉冲退化为静态边框。
// 命中：所有 glow 层 allowsHitTesting(false)，绝不参与点击。
// ============================================================

// MARK: - Reduce Motion 探测

/// 系统「减弱动态效果」偏好（effects spec: 动效可关闭与降级）。
/// 所有装饰性动效播放前必须先查这里。
@MainActor
enum MotionPreference {
    /// true = 用户开启了 系统设置 > 辅助功能 > 显示 > 减弱动态效果
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

// MARK: - 岛体形状

/// 岛体是顶部贴边形状：上方两角直角、下方两角圆角。
/// glow 描边与静态降级边框都用它，保证和岛体轮廓一致。
private func islandBorderShape(cornerRadius: CGFloat) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: cornerRadius,
        bottomTrailingRadius: cornerRadius,
        topTrailingRadius: 0,
        style: .continuous
    )
}

// MARK: - 公开 API

extension View {

    /// AI 解析中：AppleIntelligence 风格的彩虹流光呼吸（自绘旋转 AngularGradient）。
    ///
    /// - `active == false`：原样返回视图，零开销（不创建动画层）。
    /// - 减弱动态效果开启：退化为静态 accent 细边框。
    ///
    /// ⚠️ 身份稳定：条件分支只能放在 overlay/background 内部。
    /// 用 `if active { self... } else { self }` 包住宿主会改变视图身份，
    /// active 翻转瞬间整棵岛体子树被销毁重建，壳体形变动画全部失效（闪现替换）。
    func aiParsingGlow(active: Bool, cornerRadius: CGFloat) -> some View {
        self
            .overlay {
                if active && MotionPreference.reduceMotion {
                    islandBorderShape(cornerRadius: cornerRadius)
                        .strokeBorder(DS.Colors.accent.opacity(0.85), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if active && !MotionPreference.reduceMotion {
                    IslandAuroraGlow(cornerRadius: cornerRadius)
                        .allowsHitTesting(false)
                }
            }
    }

    /// 提前 1h 弱档：微弱橙光慢呼吸（F-04「弱」——有 glow 但强度最低）。
    /// 身份稳定要求同 `aiParsingGlow`。
    func nearGlow(active: Bool, cornerRadius: CGFloat) -> some View {
        self.background {
            if active && !MotionPreference.reduceMotion {
                IslandPulseGlow(cornerRadius: cornerRadius, palette: .near)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 提前 15min 中档：橙色脉冲（强度介于 near 与 urgent 之间）。
    func warningGlow(active: Bool, cornerRadius: CGFloat) -> some View {
        self
            .overlay {
                if active && MotionPreference.reduceMotion {
                    islandBorderShape(cornerRadius: cornerRadius)
                        .strokeBorder(DS.Colors.warning.opacity(0.9), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if active && !MotionPreference.reduceMotion {
                    IslandPulseGlow(cornerRadius: cornerRadius, palette: .warning)
                        .allowsHitTesting(false)
                }
            }
    }

    /// 紧急/过期：红色心跳脉冲。
    /// 身份稳定要求同 `aiParsingGlow`。
    func urgentGlow(active: Bool, cornerRadius: CGFloat) -> some View {
        self
            .overlay {
                if active && MotionPreference.reduceMotion {
                    islandBorderShape(cornerRadius: cornerRadius)
                        .strokeBorder(DS.Colors.alert.opacity(0.9), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if active && !MotionPreference.reduceMotion {
                    IslandPulseGlow(cornerRadius: cornerRadius, palette: .urgent)
                        .allowsHitTesting(false)
                }
            }
    }

    /// 完成金色高光：`trigger` 变化时播放一次 ~1s 后自动熄灭。
    ///
    ///   shape.goldFlash(trigger: store.completionFlashCount, cornerRadius: geo.cornerRadius)
    ///
    /// - 未触发 / 播完后：原样返回视图，零开销。
    /// - 减弱动态效果开启：显示 1s 静态金色边框（无动画）。
    func goldFlash(trigger: Int, cornerRadius: CGFloat) -> some View {
        modifier(GoldFlashModifier(trigger: trigger, cornerRadius: cornerRadius))
    }
}

// MARK: - 金色高光 modifier（内部状态：触发后 1s 自动复位）

struct GoldFlashModifier: ViewModifier {
    let trigger: Int
    let cornerRadius: CGFloat

    @State private var flashing = false

    func body(content: Content) -> some View {
        // 身份稳定：条件只在 overlay/background 内部（理由见 aiParsingGlow 注释）
        content
            .overlay {
                if flashing && MotionPreference.reduceMotion {
                    islandBorderShape(cornerRadius: cornerRadius)
                        .strokeBorder(DS.Colors.gold.opacity(0.85), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if flashing && !MotionPreference.reduceMotion {
                    IslandPulseGlow(cornerRadius: cornerRadius, palette: .gold)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: trigger) { _, _ in
                flashing = true
            }
            // flashing 翻 true 后启动一次 1s 倒计时；trigger 连击时旧任务被取消重计时
            .task(id: trigger) {
                guard flashing else { return }
                try? await Task.sleep(for: .seconds(1.0))
                guard !Task.isCancelled else { return }
                flashing = false
            }
    }
}

// MARK: - 脉冲光晕（near / warning / urgent / gold 共用）

/// 单色脉冲光晕：两层描边（外层弥散 + 内层贴边亮线）沿岛体轮廓，
/// 用 .plusLighter 叠加在黑色岛体与桌面上 → 通透发光感；
/// 透明度 + 模糊半径随呼吸节拍插值，强度由 palette 决定。
private struct IslandPulseGlow: View {
    let cornerRadius: CGFloat
    let palette: GlowPalette

    @State private var pulsing = false

    var body: some View {
        let shape = islandBorderShape(cornerRadius: cornerRadius)
        ZStack {
            // 外层：宽而柔的弥散光（呼吸时强度/扩散摆动最明显）
            shape
                .stroke(palette.color, lineWidth: palette.outerWidth)
                .blur(radius: pulsing ? palette.outerBlurMax : palette.outerBlurMin)
                .opacity(pulsing ? palette.outerOpacityMax : palette.outerOpacityMin)
            // 内层：贴边亮线，保证在亮背景前也可辨形
            shape
                .stroke(palette.color, lineWidth: palette.innerWidth)
                .blur(radius: palette.innerBlur)
                .opacity(pulsing ? palette.innerOpacityMax : palette.innerOpacityMin)
        }
        .blendMode(.plusLighter)
        .compositingGroup()
        .animation(
            .easeInOut(duration: palette.period).repeatForever(autoreverses: true),
            value: pulsing
        )
        .onAppear { pulsing = true }
    }
}

// MARK: - AI 极光流光（aiWorking 专用，signature 动效）

/// AppleIntelligence 风格：彩虹 AngularGradient 沿岛体轮廓缓慢旋转，
/// 叠加一层轻呼吸。这是全局唯一的「炫」动效，其余状态保持克制。
private struct IslandAuroraGlow: View {
    let cornerRadius: CGFloat

    @State private var angle: Double = 0
    @State private var breathing = false

    // appleIntelligence 调色（蓝紫 → 品红 → 红 → 橙 → 回蓝紫，首尾同色避免接缝跳变）
    private let spectrum: [Color] = [
        Color(red: 0.20, green: 0.18, blue: 1.00),
        Color(red: 0.82, green: 0.18, blue: 0.55),
        Color(red: 1.00, green: 0.13, blue: 0.13),
        Color(red: 1.00, green: 0.62, blue: 0.18),
        Color(red: 0.42, green: 0.24, blue: 1.00),
        Color(red: 0.20, green: 0.18, blue: 1.00)
    ]

    var body: some View {
        let shape = islandBorderShape(cornerRadius: cornerRadius)
        let gradient = AngularGradient(
            gradient: Gradient(colors: spectrum),
            center: .center,
            angle: .degrees(angle)
        )
        ZStack {
            shape
                .stroke(gradient, lineWidth: 7)
                .blur(radius: breathing ? 16 : 11)
                .opacity(breathing ? 0.85 : 0.6)
            shape
                .stroke(gradient, lineWidth: 2.5)
                .blur(radius: 2)
                .opacity(0.9)
        }
        .blendMode(.plusLighter)
        .compositingGroup()
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                angle = 360
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

// MARK: - 调色板（颜色来源 token 见各行注释）

/// 脉冲光晕的强度参数。三档递进（F-04）：near 弱 < warning 中 < urgent 强
/// （对比 opacity / blur / period：越紧急越亮、越快）。
private struct GlowPalette {
    let color: Color
    let outerWidth: CGFloat
    let outerBlurMin: CGFloat
    let outerBlurMax: CGFloat
    let outerOpacityMin: Double
    let outerOpacityMax: Double
    let innerWidth: CGFloat
    let innerBlur: CGFloat
    let innerOpacityMin: Double
    let innerOpacityMax: Double
    let period: Double

    /// 提前 1h：微弱橙光慢呼吸 —— DS.Colors.warning
    static let near = GlowPalette(
        color: DS.Colors.warning,
        outerWidth: 5, outerBlurMin: 6, outerBlurMax: 11,
        outerOpacityMin: 0.18, outerOpacityMax: 0.40,
        innerWidth: 2, innerBlur: 1.5,
        innerOpacityMin: 0.30, innerOpacityMax: 0.55,
        period: 1.9
    )

    /// 提前 15min：橙色中档脉冲 —— DS.Colors.warning
    static let warning = GlowPalette(
        color: DS.Colors.warning,
        outerWidth: 6, outerBlurMin: 7, outerBlurMax: 14,
        outerOpacityMin: 0.30, outerOpacityMax: 0.62,
        innerWidth: 2.5, innerBlur: 1.5,
        innerOpacityMin: 0.45, innerOpacityMax: 0.78,
        period: 1.1
    )

    /// 过期：红色强心跳脉冲 —— DS.Colors.alert #FF6B61
    static let urgent = GlowPalette(
        color: DS.Colors.alert,
        outerWidth: 7, outerBlurMin: 8, outerBlurMax: 16,
        outerOpacityMin: 0.35, outerOpacityMax: 0.80,
        innerWidth: 3, innerBlur: 1.5,
        innerOpacityMin: 0.55, innerOpacityMax: 0.95,
        period: 0.72
    )

    /// 完成金色高光 —— DS.Colors.gold
    static let gold = GlowPalette(
        color: DS.Colors.gold,
        outerWidth: 7, outerBlurMin: 8, outerBlurMax: 16,
        outerOpacityMin: 0.45, outerOpacityMax: 0.85,
        innerWidth: 3, innerBlur: 1.5,
        innerOpacityMin: 0.60, innerOpacityMax: 1.0,
        period: 0.6
    )
}
