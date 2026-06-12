import AppKit
import SwiftGlow
import SwiftUI

// ============================================================
// Glow 动效封装（effects spec）—— 给岛体形状用的三个 View 扩展。
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
// 性能契约：active == false / 未触发时直接返回原视图，不挂 Metal 层。
// 可访问性：系统「减弱动态效果」开启时，流光/脉冲退化为静态边框。
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

// MARK: - 岛体形状（静态降级边框用）

/// 岛体是顶部贴边形状：上方两角直角、下方两角圆角。
/// 静态降级边框用它，保证和岛体轮廓一致。
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

    /// AI 解析中：AppleIntelligence 风格的彩虹流光呼吸（SwiftGlow Metal 渲染）。
    ///
    /// - `active == false`：原样返回视图，零开销（不创建 Metal 层）。
    /// - 减弱动态效果开启：退化为静态 accent 细边框。
    /// - glow 用 `.behind` placement 向外溢出，岛体贴屏幕顶边，
    ///   所以流光主要在下沿和左右两侧可见（符合预期）。
    ///
    /// 用法：`shape.aiParsingGlow(active: state == .aiWorking, cornerRadius: geo.cornerRadius)`
    @ViewBuilder
    func aiParsingGlow(active: Bool, cornerRadius: CGFloat) -> some View {
        if !active {
            self
        } else if MotionPreference.reduceMotion {
            // 降级：静态 accent 边框（无动画、无 Metal）
            self.overlay(
                islandBorderShape(cornerRadius: cornerRadius)
                    .strokeBorder(DS.Colors.accent.opacity(0.85), lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
        } else {
            self.animatedGlow(
                states: IslandGlowStates.aiParsing(cornerRadius: cornerRadius),
                status: .default
            )
        }
    }

    /// 紧急/过期：红色脉冲 glow。
    ///
    /// - `active == false`：原样返回视图，零开销。
    /// - 减弱动态效果开启：退化为静态红色细边框。
    ///
    /// 用法：`shape.urgentGlow(active: state == .urgent, cornerRadius: geo.cornerRadius)`
    @ViewBuilder
    func urgentGlow(active: Bool, cornerRadius: CGFloat) -> some View {
        if !active {
            self
        } else if MotionPreference.reduceMotion {
            // 降级：静态 alert 红边框
            self.overlay(
                islandBorderShape(cornerRadius: cornerRadius)
                    .strokeBorder(DS.Colors.alert.opacity(0.9), lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
        } else {
            self.animatedGlow(
                states: IslandGlowStates.urgent(cornerRadius: cornerRadius),
                status: .default
            )
        }
    }

    /// 完成金色高光：`trigger` 变化时播放一次 ~1s 后自动熄灭。
    ///
    /// 调用方维护一个递增计数（每完成一个 todo +1）传进来即可：
    ///
    ///   shape.goldFlash(trigger: store.completionFlashCount, cornerRadius: geo.cornerRadius)
    ///
    /// - 未触发 / 播完后：原样返回视图，零开销。
    /// - 减弱动态效果开启：显示 1s 静态金色边框（无流光动画）。
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
        Group {
            if !flashing {
                content
            } else if MotionPreference.reduceMotion {
                content.overlay(
                    islandBorderShape(cornerRadius: cornerRadius)
                        .strokeBorder(DS.Colors.gold.opacity(0.85), lineWidth: 1.5)
                        .allowsHitTesting(false)
                )
            } else {
                content.animatedGlow(
                    states: IslandGlowStates.gold(cornerRadius: cornerRadius),
                    status: .default
                )
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

// MARK: - Glow 配置工厂（颜色注释标明来源 token）

/// 岛体专用的 SwiftGlow 状态配置。
/// 注意：SwiftGlow 颜色只收 CSS 字符串，此处硬编码 RGB 值，来源 token 见各行注释。
enum IslandGlowStates {

    /// AI 解析流光：AppleIntelligence 调色（蓝紫→品红→橙），placement .behind 向外溢光
    static func aiParsing(cornerRadius: CGFloat) -> [GlowState] {
        [
            GlowState(
                name: .default,
                preset: .css(
                    cornerRadius: Float(cornerRadius),
                    outlineWidth: 0, // 边框被黑色岛体盖住，画了也看不见，省掉
                    animationSpeed: 1.2,
                    glowLayers: [
                        // 外层弥散呼吸（颜色取自 SwiftGlow appleIntelligence 预设色板）
                        GlowLayerConfig(
                            cssColors: ["rgba(50, 45, 255, 1)", "rgba(209, 45, 141, 1)", "rgba(255, 33, 33, 1)", "rgba(255, 159, 47, 1)"],
                            opacity: 0.40, glowSize: [14, 22, 14], speedMultiplier: 1,
                            glowPlacement: .behind, coverage: 1
                        ),
                        // 中层主光带
                        GlowLayerConfig(
                            cssColors: ["rgba(106, 60, 255, 1)", "rgba(255, 99, 203, 1)", "rgba(255, 68, 125, 1)", "rgba(255, 212, 152, 1)"],
                            opacity: 0.65, glowSize: [6], speedMultiplier: 1,
                            glowPlacement: .behind, coverage: 1
                        ),
                        // 高速白色流星点缀
                        GlowLayerConfig(
                            cssColors: ["rgba(255, 255, 255, 1)"],
                            opacity: 0.22, glowSize: [0, 3, 0], speedMultiplier: 2,
                            glowPlacement: .behind, coverage: 0.4
                        )
                    ]
                )
            )
        ]
    }

    /// 紧急红色脉冲：glowSize 关键帧 [5,16,5] + animationSpeed 3 产生心跳脉冲感
    static func urgent(cornerRadius: CGFloat) -> [GlowState] {
        [
            GlowState(
                name: .default,
                preset: .css(
                    cornerRadius: Float(cornerRadius),
                    outlineWidth: 0,
                    animationSpeed: 3,
                    glowLayers: [
                        // 外层弥散脉冲 —— rgba(255,107,97) = DS.Colors.alert #FF6B61
                        GlowLayerConfig(
                            cssColors: ["rgba(255, 107, 97, 1)", "rgba(255, 45, 45, 1)", "rgba(255, 107, 97, 1)"],
                            opacity: 0.45, glowSize: [5, 16, 5], speedMultiplier: 1,
                            glowPlacement: .behind, coverage: 1
                        ),
                        // 内层紧贴红边 —— DS.Colors.alert
                        GlowLayerConfig(
                            cssColors: ["rgba(255, 107, 97, 1)", "rgba(255, 70, 60, 1)"],
                            opacity: 0.8, glowSize: [3, 7, 3], speedMultiplier: 1,
                            glowPlacement: .behind, coverage: 1
                        )
                    ]
                )
            )
        ]
    }

    /// 完成金色高光 —— rgba(255,214,0) = DS.Colors.gold (1.0, 0.84, 0.0)
    static func gold(cornerRadius: CGFloat) -> [GlowState] {
        [
            GlowState(
                name: .default,
                preset: .css(
                    cornerRadius: Float(cornerRadius),
                    outlineWidth: 0,
                    animationSpeed: 2,
                    glowLayers: [
                        // 外层金色弥散 —— DS.Colors.gold
                        GlowLayerConfig(
                            cssColors: ["rgba(255, 214, 0, 1)", "rgba(255, 240, 150, 1)", "rgba(255, 214, 0, 1)"],
                            opacity: 0.5, glowSize: [8, 18, 8], speedMultiplier: 1,
                            glowPlacement: .behind, coverage: 1
                        ),
                        // 内层亮金描边
                        GlowLayerConfig(
                            cssColors: ["rgba(255, 230, 120, 1)", "rgba(255, 214, 0, 1)"],
                            opacity: 0.9, glowSize: [3, 6, 3], speedMultiplier: 1.5,
                            glowPlacement: .behind, coverage: 1
                        )
                    ]
                )
            )
        ]
    }
}
