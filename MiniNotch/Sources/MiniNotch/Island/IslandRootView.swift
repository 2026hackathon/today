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

    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?

    private var geo: IslandGeometry {
        IslandGeometry.geometry(for: store.islandState, notchSize: notchSize)
    }

    var body: some View {
        islandBody
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var islandBody: some View {
        content
            .frame(width: geo.width)
            .frame(height: geo.height)
            .frame(minHeight: max(notchSize.height, 32))
            .background(NotchShape(cornerRadius: geo.cornerRadius).fill(DS.Colors.islandBG))
            .clipShape(NotchShape(cornerRadius: geo.cornerRadius))
            // ── 动效挂载（effects spec）──
            .touchdownRipple(source: $store.landedSource)
            .overlay {
                if store.settings.effectsEnabled {
                    ConfettiBurst(trigger: store.completionFlash)
                        .allowsHitTesting(false)
                }
            }
            .aiParsingGlow(active: store.islandState == .aiWorking, cornerRadius: geo.cornerRadius)
            .urgentGlow(active: store.islandState == .urgent, cornerRadius: geo.cornerRadius)
            .goldFlash(trigger: store.completionFlash, cornerRadius: geo.cornerRadius)
            .shadow(color: .black.opacity(store.islandState.isCompact ? 0 : 0.35), radius: 14, y: 6)
            .contentShape(NotchShape(cornerRadius: geo.cornerRadius))
            .onTapGesture { handleTap() }
            .onHover { handleHover($0) }
            // 卡片态自动收回：newTask 悬浮 4s 后回落，悬停暂停（F-07）
            .task(id: autoDismissKey) { await autoDismissIfNeeded() }
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
            NewTaskCard(draft: draft)

        case .reminder(let todo):
            ReminderCard(todo: todo)

        case .batch(let drafts):
            BatchCard(drafts: drafts)

        case .quickInput:
            QuickInputCard(onParse: onParse)

        case .expanded(let tab):
            if tab == .settings {
                SettingsPanel()
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
            store.present(.expanded(tab: .today))
        case .expanded:
            store.dismiss()
        default:
            break // 卡片态点空白不收起，避免误触丢草稿
        }
    }

    /// hover ≥0.8s 弹预览，移出 0.3s 收回（island-shell spec）
    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        hoverTask?.cancel()
        hoverTask = Task { [hovering] in
            if hovering {
                guard store.islandState.isCompact, store.islandState != .aiWorking else { return }
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled, isHovering, store.islandState.isCompact else { return }
                store.present(.hoverPreview)
            } else {
                guard store.islandState == .hoverPreview else { return }
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled, !isHovering else { return }
                store.dismiss()
            }
        }
    }

    // MARK: - 卡片自动收回

    private var autoDismissKey: String {
        if case .newTask(let draft) = store.islandState { return "newTask-\(draft.id)" }
        return ""
    }

    private func autoDismissIfNeeded() async {
        guard case .newTask = store.islandState else { return }
        try? await Task.sleep(for: .seconds(4))
        // 悬停期间暂停倒计时
        while isHovering {
            try? await Task.sleep(for: .seconds(0.5))
            if Task.isCancelled { return }
        }
        guard !Task.isCancelled, case .newTask = store.islandState else { return }
        store.dismiss()
    }
}

// MARK: - 刘海形状（上沿直角贴屏、下沿圆角）

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 10

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
