import AppKit
import SwiftUI

// ============================================================
// 全屏庆祝（effects spec: 完成今日全部任务时触发）
//
// 独立全屏透明窗口（不能撑大 notch 面板，见 design.md 决策表），
// 半透明暗背景 + 中心皇冠卡片 + 底部多点烟花（错峰 3 波），
// 3.5s 后自动淡出关窗。绝不抢焦点、不吃鼠标事件。
//
// 用法（AppStore 检测到今日未完成数归零时调用）：
//
//   CelebrationWindowController.shared.celebrate(streakDays: store.streakDays)
//
// 降级：系统「减弱动态效果」开启时只显示文字卡 1.5s，无烟花无暗背景。
// ============================================================

@MainActor
final class CelebrationWindowController {
    static let shared = CelebrationWindowController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// 播放全屏庆祝动画，3-4s 后自动关窗释放。重复调用会重启动画。
    /// - Parameter streakDays: 连续清空天数（显示「连续 N 天清空」，<= 0 时不显示该行）
    func celebrate(streakDays: Int) {
        // 重入保护：取消上一次的关窗倒计时并拆掉旧窗
        dismissTask?.cancel()
        teardown()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let reduceMotion = MotionPreference.reduceMotion

        // 全屏透明面板（参考 NotchPanel：nonactivating + 全 Space + 盖全屏 App）
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true          // 纯展示层，绝不挡鼠标
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.contentView = NSHostingView(
            rootView: CelebrationView(streakDays: streakDays, reduceMotion: reduceMotion)
        )

        panel.alphaValue = 0
        panel.orderFrontRegardless()             // 显示但不激活 App、不抢焦点
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }

        // 减弱动态效果：只展示文字卡 1.5s；正常：3.5s 后淡出
        let displaySeconds: Double = reduceMotion ? 1.5 : 3.5
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(displaySeconds))
            guard !Task.isCancelled else { return }
            self?.beginFadeOut()
            // 等淡出动画（0.4s）播完再拆窗
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            self?.teardown()
        }
    }

    // MARK: - 私有

    private func beginFadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 0
        }
    }

    /// 关窗并释放（contentView 置 nil 让 NSHostingView/Metal 资源立刻回收）
    private func teardown() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

// MARK: - 庆祝内容视图

/// 半透明暗背景 + 中心皇冠卡片 + 底部 5 个发射点错峰 3 波烟花。
/// reduceMotion = true 时只显示文字卡（无暗背景、无粒子、无 pop 动画）。
struct CelebrationView: View {
    let streakDays: Int
    let reduceMotion: Bool

    /// 卡片 pop-in
    @State private var cardVisible = false
    /// 两组烟花发射点的触发计数（A 组 3 点 / B 组 2 点，交替成 3 波）
    @State private var waveA = 0
    @State private var waveB = 0

    /// A 组发射点（底部边缘，y 略超出屏幕让粒子"破地而出"）
    private static let emittersA: [UnitPoint] = [
        UnitPoint(x: 0.15, y: 1.02),
        UnitPoint(x: 0.50, y: 1.02),
        UnitPoint(x: 0.85, y: 1.02)
    ]
    /// B 组发射点（错位，第二波）
    private static let emittersB: [UnitPoint] = [
        UnitPoint(x: 0.32, y: 1.02),
        UnitPoint(x: 0.68, y: 1.02)
    ]

    var body: some View {
        ZStack {
            if !reduceMotion {
                // 半透明暗背景压暗桌面，聚焦中心卡片
                Color.black.opacity(0.55)
                    .ignoresSafeArea()

                // 底部烟花：每个 ConfettiBurst 铺满全屏、各自从自己的发射点喷射
                ForEach(Array(Self.emittersA.enumerated()), id: \.offset) { _, point in
                    ConfettiBurst(trigger: waveA, origin: point, mode: .fountain, particleCount: 32)
                        .ignoresSafeArea()
                }
                ForEach(Array(Self.emittersB.enumerated()), id: \.offset) { _, point in
                    ConfettiBurst(trigger: waveB, origin: point, mode: .fountain, particleCount: 32)
                        .ignoresSafeArea()
                }
            }

            card
                .scaleEffect(cardVisible ? 1 : 0.5)
                .opacity(cardVisible ? 1 : 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            if reduceMotion {
                cardVisible = true
            } else {
                // 皇冠卡片 pop-in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    cardVisible = true
                }
            }
        }
        .task {
            // 错峰 3 波烟花：A → B → A
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(0.15))
            guard !Task.isCancelled else { return }
            waveA += 1
            try? await Task.sleep(for: .seconds(0.85))
            guard !Task.isCancelled else { return }
            waveB += 1
            try? await Task.sleep(for: .seconds(0.85))
            guard !Task.isCancelled else { return }
            waveA += 1
        }
    }

    /// 中心卡片：皇冠 + 「今日完美收官」+ 「连续 N 天清空」
    /// （字号 18/12 来自 effects 任务说明 / prototype celebration 区）
    private var card: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 36))
                .foregroundStyle(DS.Colors.gold)

            Text("今日完美收官")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.Colors.text1)

            if streakDays > 0 {
                Text("连续 \(streakDays) 天清空")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.text2)
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 26)
        .background(
            DS.Colors.islandBG.opacity(0.9), // 来源 token: DS.Colors.islandBG
            in: RoundedRectangle(cornerRadius: DS.Radius.island, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.island, style: .continuous)
                .strokeBorder(DS.Colors.border, lineWidth: 1)
        )
    }
}
