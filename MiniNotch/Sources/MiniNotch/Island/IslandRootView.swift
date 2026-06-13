import SwiftUI

// ============================================================
// IslandRootView —— 状态机 → 视图路由 + 岛体形变 + 动效挂载。
// island 的一切形态变化都从这里走（island-shell spec）。
// ============================================================

struct IslandRootView: View {
    @EnvironmentObject var store: AppStore

    let notchSize: CGSize
    /// ⌘N / quickInput 的 AI 解析（AppDelegate 注入，走 AIService）
    let onParse: (String) async -> TodoDraft?
    /// agentLanded 卡点击跳转终端（AppDelegate 注入，走 AgentSessionService）
    var onJumpToAgent: (AgentSession) -> Void = { _ in }
    /// 面板穿透命中区域：上报岛体当前壳体尺寸，让岛体之外的透明区点击穿透（AppDelegate 注入）
    var hitRegion: IslandHitRegion? = nil

    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    /// 壳体动画高度：实测内容自然高度后由弹簧驱动插值。
    /// 不能依赖内容自适应（height=nil 时分支切换没有可插值的量，壳体会闪现替换）
    @State private var measuredContentHeight: CGFloat = 0

    private var geo: IslandGeometry {
        IslandGeometry.geometry(
            for: store.islandState, notchSize: notchSize,
            agentBadgeWidth: agentBadgeWidth
        )
    }

    var body: some View {
        islandBody
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 左翼徽章额外宽度：agent 运行中 ⚙ + 等待 🔔 + 提前准备 ⏳ 各约 42pt（都在左翼并排）
    private var agentBadgeWidth: CGFloat {
        guard store.islandState.isCompact else { return 0 }
        var w: CGFloat = 0
        if store.activeAgentCount > 0 { w += 42 }
        if store.waitingAgentCount > 0 { w += 42 }
        if store.hasPrepBadge { w += 42 }
        return w
    }

    /// 壳体当前应显示的高度：固定几何态直接用配置值，内容态用实测值
    private var shellHeight: CGFloat {
        max(geo.height ?? measuredContentHeight, max(notchSize.height, 32))
    }

    private var islandBody: some View {
        content
            // 灵动岛编舞：旧内容速隐 → 壳体拉伸 → 新内容带模糊浮现
            .transition(IslandTransition.content)
            .frame(width: geo.width)
            .frame(height: geo.height)
            // 实测内容自然高度（在裁切窗口之前测，拿到的是完整尺寸）
            .background(GeometryReader { proxy in
                Color.clear.preference(key: IslandContentHeightKey.self, value: proxy.size.height)
            })
            // 壳体窗口：高度是显式数值 → 弹簧可插值"拉长"；顶对齐保证只向下生长
            .frame(width: geo.width, height: shellHeight, alignment: .top)
            // 上报壳体真实尺寸 → 面板按此裁剪命中范围，岛体外透明区点击穿透
            .background(GeometryReader { proxy in
                Color.clear.preference(key: IslandShellSizeKey.self, value: proxy.size)
            })
            .background(NotchShape(cornerRadius: geo.cornerRadius).fill(DS.Colors.islandBG))
            .clipShape(NotchShape(cornerRadius: geo.cornerRadius))
            // ── 动效挂载（effects spec）──
            .touchdownRipple(color: $store.landedRippleColor)
            .overlay {
                if store.settings.effectsEnabled {
                    ConfettiBurst(trigger: store.completionFlash)
                        .allowsHitTesting(false)
                }
            }
            .aiParsingGlow(active: store.islandState == .aiWorking, cornerRadius: geo.cornerRadius)
            // F-04 三档递进 glow：1h 微弱橙呼吸 → 15min 橙色脉冲 → 过期红色强脉冲
            .nearGlow(active: store.islandState == .near, cornerRadius: geo.cornerRadius)
            .warningGlow(
                active: store.islandState == .urgent && store.overdueTodos.isEmpty && !store.debugForceRedGlow,
                cornerRadius: geo.cornerRadius
            )
            .urgentGlow(
                active: store.islandState == .urgent && (!store.overdueTodos.isEmpty || store.debugForceRedGlow),
                cornerRadius: geo.cornerRadius
            )
            .goldFlash(trigger: store.completionFlash, cornerRadius: geo.cornerRadius)
            .shadow(color: .black.opacity(store.islandState.isCompact ? 0 : 0.35), radius: 14, y: 6)
            .contentShape(NotchShape(cornerRadius: geo.cornerRadius))
            // 右键退出（重写壳子时从旧 NotchView 丢失过，勿删）
            .contextMenu {
                Button("退出 TodoIsland") {
                    NSApp.terminate(nil)
                }
            }
            .onTapGesture { handleTap() }
            .onHover { handleHover($0) }
            .onPreferenceChange(IslandContentHeightKey.self) { newHeight in
                Task { @MainActor in applyMeasuredHeight(newHeight) }
            }
            .onPreferenceChange(IslandShellSizeKey.self) { size in
                Task { @MainActor in hitRegion?.islandSize = size }
            }
    }

    private func applyMeasuredHeight(_ newHeight: CGFloat) {
        guard newHeight > 0, newHeight != measuredContentHeight else { return }
        if measuredContentHeight == 0 {
            measuredContentHeight = newHeight   // 启动首帧直接就位，不播动画
        } else {
            withAnimation(IslandAnimation.spring) { measuredContentHeight = newHeight }
        }
    }

    // MARK: - 状态 → 视图路由

    @ViewBuilder
    private var content: some View {
        switch store.islandState {
        case .idle, .normal, .near, .urgent, .aiWorking, .justCompleted, .celebrate:
            CompactContent(state: store.islandState, notchWidth: notchSize.width)
                .frame(height: max(notchSize.height, 32))

        case .hoverPreview:
            HoverPreview()
                .padding(.top, max(notchSize.height, 32) + 4)

        case .newTask(let draft):
            // .id 绑定视图身份：连续两次截图时第二张卡不残留上一张的 @State 草稿（review-fixes #7）
            NewTaskCard(draft: draft).id(draft.id)

        case .reminder(let todo):
            ReminderCard(todo: todo)

        case .batch(let drafts):
            BatchCard(drafts: drafts).id(drafts.map(\.id))

        case .quickInput:
            QuickInputCard(onParse: onParse)

        case .editTask(let todo):
            EditTaskCard(todo: todo).id(todo.id)

        case .jiraLanded(let item, let moreCount):
            JiraLandedCard(item: item, moreCount: moreCount)

        case .messageLanded(let message, let moreCount):
            MessageLandedCard(message: message, moreCount: moreCount)

        case .agentLanded(let session):
            AgentLandedCard(session: session, onJump: onJumpToAgent)

        case .prepReminder(let todo, let moreCount):
            PrepReminderCard(todo: todo, moreCount: moreCount)

        case .expanded(let tab):
            if tab == .settings {
                SettingsPanel()
            } else if tab == .calendar {
                CalendarPanel()
            } else {
                TodayPanel()
            }

        case .morningReport(let text):
            MorningReportPanel(text: text)

        case .eveningReport(let text):
            EveningReportPanel(text: text)
        }
    }

    // MARK: - 交互

    private func handleTap() {
        switch store.islandState {
        case _ where store.islandState.isCompact, .hoverPreview:
            // 点击 = 不等悬停延迟，立即展开
            store.present(.expanded(tab: .today))
        case .expanded:
            break // 面板由悬停驱动，点击面板空白不收起（移出/esc/失焦才收）
        default:
            break // 卡片态点空白不收起，避免误触丢草稿
        }
    }

    /// 悬停 0.25s 直接展开完整面板（无中间预览态），移出 0.2s 收回（island-shell spec）
    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()
        hoverTask = Task { [hovering] in
            if hovering {
                guard store.islandState.isCompact, store.islandState != .aiWorking else { return }
                try? await Task.sleep(for: .seconds(0.25))
                guard !Task.isCancelled, isHovering, store.islandState.isCompact else { return }
                store.present(.expanded(tab: .today))
            } else {
                // 悬停驱动的态（预览/展开面板）移出即收；卡片/输入态不受影响
                guard isHoverDriven(store.islandState) else { return }
                try? await Task.sleep(for: .seconds(0.2))
                // 菜单跟踪中（Debug/右键菜单）鼠标在菜单上不算离开（review-fixes #12）；
                // 确认弹窗打开时（删除二次确认）也不收起，否则移向弹窗按钮途中会把弹窗一起收掉
                guard !Task.isCancelled, !isHovering, !store.isMenuTracking,
                      store.dialogPresentedCount == 0, !store.screenshotViewerOpen else { return }
                store.dismiss()
            }
        }
    }

    private func isHoverDriven(_ state: IslandState) -> Bool {
        switch state {
        case .expanded(let tab):
            // 设置页在打字（API Key 等），鼠标移出不收起；esc / 失焦仍可收
            tab != .settings
        case .hoverPreview:
            true
        default:
            false
        }
    }

    // newTask 是「需要用户决策」的可操作卡（保存/忽略），不设倒计时自动收回——
    // 否则用户还没想清楚卡就消失了。点击别处（失焦）仍会正常关闭，不会一直占着刘海。
    // 纯通知类卡（jiraLanded/messageLanded/agentLanded）的自动收回另有处理，不走这里。
}

// MARK: - 内容过渡（灵动岛节奏）

/// 旧内容 0.09s 速隐（避免新旧重影）；新内容延迟 0.1s 带模糊+微缩放浮现，
/// 时序上正好衔接壳体弹簧拉伸的中后段
private enum IslandTransition {
    // AnyTransition 非 Sendable，Swift 6 下不能做静态存储属性，用计算属性
    static var content: AnyTransition { AnyTransition.asymmetric(
        insertion: .modifier(
            active: BlurFade(blur: 8, opacity: 0, scale: 0.97),
            identity: BlurFade(blur: 0, opacity: 1, scale: 1)
        )
        .animation(.easeOut(duration: 0.18).delay(0.1)),
        removal: .modifier(
            active: BlurFade(blur: 6, opacity: 0, scale: 1),
            identity: BlurFade(blur: 0, opacity: 1, scale: 1)
        )
        .animation(.easeIn(duration: 0.09))
    ) }
}

private struct BlurFade: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
    }
}

/// 内容自然高度上报（取 max：分支切换瞬间新旧并存，目标高度以高者为准）
private struct IslandContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 壳体当前渲染尺寸上报（面板穿透命中用）：取较大者，盖住形变瞬间新旧并存
private struct IslandShellSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

// MARK: - 刘海形状（上沿直角贴屏、下沿圆角）

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 10

    /// 让 compact(18) ↔ 展开(24) 的圆角跟随形变渐变而不是跳变
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        path.addArc(
            center: CGPoint(x: rect.width - r, y: rect.height - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: r, y: rect.height))
        path.addArc(
            center: CGPoint(x: r, y: rect.height - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
