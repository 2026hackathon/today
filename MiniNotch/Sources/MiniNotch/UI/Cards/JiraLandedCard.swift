import AppKit
import SwiftUI

// ============================================================
// JiraLandedCard —— 外部 ticket 新分配通知卡（jira-landed-card spec）。
// Jira ticket 与 GitHub PR 共用，文案/图标/颜色按 todo.source 区分。
// 与 NewTaskCard 的区别：纯通知，ticket 已自动入库，无需任何操作。
//   - 底部倒计时进度条（5s），走完播放「收入灵动岛」动效后回落
//   - 悬停暂停倒计时
//   - 点击卡片任意位置 → 浏览器打开 ticket（并立即收回）
// ============================================================

struct JiraLandedCard: View {
    let todo: Todo
    /// 同轮其余新分配数（>0 显示「等 N 条新分配」）
    let moreCount: Int
    @EnvironmentObject var store: AppStore

    /// 倒计时总时长（秒）
    private static let duration: Double = 5.0

    @State private var remaining = JiraLandedCard.duration
    @State private var hovering = false
    @State private var collecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            titleBlock
            metaRow
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 36) // 摄像头区留位
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { countdownBar }
        // 「收入灵动岛」：内容向顶部缩入并淡出，随后岛体弹簧回缩（store.dismiss）
        .scaleEffect(collecting ? 0.05 : 1, anchor: .top)
        .opacity(collecting ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { openAndCollect() }
        .onHover { hovering = $0 }
        .task(id: todo.id) { await runCountdown() }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: todo.source == .github ? "arrow.triangle.pull" : "scope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sourceColor)
            Text(todo.source == .github ? "新 PR 待处理" : "新 Jira 分配")
                .font(DS.Fonts.meta.weight(.medium))
                .foregroundStyle(DS.Colors.text2)
            Spacer(minLength: 0)
            if let status = todo.jiraStatus {
                Text(status).dsTag()
            }
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
        .padding(.bottom, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let key = todo.jiraKey {
                Text(key)
                    .font(DS.Fonts.compactSide.weight(.semibold))
                    .foregroundStyle(DS.Colors.accent)
            }
            Text(todo.title)
                .font(DS.Fonts.cardTitle)
                .foregroundStyle(DS.Colors.text1)
                .lineLimit(2)
        }
        .padding(.bottom, 10)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            PanelPriorityTag(priority: todo.priority)
            if let sp = todo.storyPointsLabel {
                Text(sp).dsTag()
            }
            if let assigner = todo.jiraAssigner {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill").font(.system(size: 8))
                    Text(todo.source == .github ? "\(assigner) 发起" : "\(assigner) 指派")
                }
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text2)
            }
            if let due = todo.dueDate {
                Text(PanelFormat.due(due))
                    .font(DS.Fonts.meta)
                    .foregroundStyle(DS.Colors.text3)
            }
            if moreCount > 0 {
                Text(todo.source == .github ? "等 \(moreCount + 1) 个新 PR" : "等 \(moreCount + 1) 条新分配")
                    .dsTag(DS.Colors.accent, bg: DS.Colors.accentSoft)
            }
            Spacer(minLength: 0)
            Text("点击查看")
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.bottom, 6)
    }

    /// 底部倒计时进度条：从满宽收缩到 0，悬停暂停
    private var countdownBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(sourceColor.opacity(0.8))
                .frame(width: geo.size.width * remaining / Self.duration, height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }

    /// 来源色（Jira 蓝 / GitHub 紫，与 Touchdown 涟漪同色）
    private var sourceColor: Color { DS.sourceColor(todo.source) }

    // MARK: - 倒计时与收回

    private func runCountdown() async {
        while remaining > 0 {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            if !hovering {
                remaining = max(0, remaining - 0.05)
            }
        }
        await collect()
    }

    private func openAndCollect() {
        if let url = todo.jiraURL {
            NSWorkspace.shared.open(url)
        }
        Task { await collect() }
    }

    private func collect() async {
        guard !collecting else { return }
        withAnimation(.easeIn(duration: 0.22)) { collecting = true }
        try? await Task.sleep(for: .milliseconds(220))
        // 倒计时期间状态可能已被其他事件抢占（如到期提醒），只在仍是本卡时回落
        if case .jiraLanded(let current, _) = store.islandState, current.id == todo.id {
            store.dismiss()
        }
    }
}
