import AppKit
import SwiftUI

// ============================================================
// PrepReminderCard —— 提前准备卡（prep-reminder-card spec）。
// lead（提前量）到点时按优先级分级呈现：
//   - 高优先级：无倒计时，常驻；「知道了」/点外侧收起后在 compact 留提前准备徽章
//   - 中优先级：底部 6s 倒计时条（悬停暂停），走完完全收回，不留徽章
// 文案随 kind 区分（日程「去准备」/ 其余「该开始」）。仿 JiraLandedCard 骨架。
// ============================================================

struct PrepReminderCard: View {
    let todo: Todo
    /// 同轮其余待准备数（>0 显示「还有 N 项要准备」）
    let moreCount: Int
    @EnvironmentObject var store: AppStore

    /// 中优先级倒计时总时长（秒）
    private static let duration: Double = 6.0

    @State private var remaining = PrepReminderCard.duration
    @State private var hovering = false
    @State private var collecting = false

    /// 高优先级 = 常驻（无倒计时，留徽章）
    private var isSticky: Bool { todo.priority == .high }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            titleBlock
            metaRow
            if isSticky { stickyActions }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 36) // 摄像头区留位
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { if !isSticky { countdownBar } }
        // 「收入灵动岛」：内容向顶部缩入并淡出，随后岛体弹簧回缩
        .scaleEffect(collecting ? 0.05 : 1, anchor: .top)
        .opacity(collecting ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !isSticky { Task { await collect() } } }
        .onHover { hovering = $0 }
        // 中优先级：6s 倒计时自动收回；高优先级无倒计时，等用户操作
        .task(id: todo.id) { if !isSticky { await runCountdown() } }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            Text("提前准备")
                .font(DS.Fonts.meta.weight(.medium))
                .foregroundStyle(DS.Colors.text2)
            Text(todo.kind.label).dsTag()
            Spacer(minLength: 0)
            Text(dueLabel)
                .dsTag(accent, bg: DS.Colors.accentSoft)
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
        .padding(.bottom, 10)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(actionVerb)
                .font(DS.Fonts.compactSide.weight(.semibold))
                .foregroundStyle(accent)
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
            if moreCount > 0 {
                Text("还有 \(moreCount) 项要准备")
                    .dsTag(DS.Colors.accent, bg: DS.Colors.accentSoft)
            }
            Spacer(minLength: 0)
            if !isSticky {
                Text("点击收起")
                    .font(DS.Fonts.tag)
                    .foregroundStyle(DS.Colors.text3)
                    .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.bottom, isSticky ? 12 : 6)
    }

    /// 高优先级常驻态的操作行：「知道了」收成徽章
    private var stickyActions: some View {
        Button("知道了") { store.acknowledgePrep(todo) }
            .buttonStyle(DSPrimaryButtonStyle())
            .overlay(alignment: .top) {
                Text("临近时会再次提醒")
                    .font(DS.Fonts.tag)
                    .foregroundStyle(DS.Colors.text3)
                    .offset(y: -18)
                    .opacity(hovering ? 1 : 0)
            }
    }

    /// 底部倒计时进度条（仅中优先级）：从满宽收缩到 0，悬停暂停
    private var countdownBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(accent.opacity(0.8))
                .frame(width: geo.size.width * remaining / Self.duration, height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }

    // MARK: - 派生

    /// 提前准备的强调色：高优先级用 warning 橙（更醒目），中用 accent
    private var accent: Color { isSticky ? DS.Colors.warning : DS.Colors.accent }

    /// 行动动词随 kind 区分
    private var actionVerb: String {
        switch todo.kind {
        case .event: "去准备"
        case .reminder: "该处理"
        case .task: "该开始"
        }
    }

    /// 距截止：< 60min 显示「N 分钟后」，否则用短标签（今晚 18:00 / 明天 …）
    private var dueLabel: String {
        guard let due = todo.effectiveDue else { return "待准备" }
        let mins = Int((due.timeIntervalSinceNow / 60).rounded(.up))
        if mins <= 0 { return "即将开始" }
        if mins < 60 { return "\(mins) 分钟后" }
        return due.dsShortLabel
    }

    // MARK: - 倒计时与收回（中优先级）

    private func runCountdown() async {
        while remaining > 0 {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            if !hovering { remaining = max(0, remaining - 0.05) }
        }
        await collect()
    }

    private func collect() async {
        guard !collecting else { return }
        withAnimation(.easeIn(duration: 0.22)) { collecting = true }
        try? await Task.sleep(for: .milliseconds(220))
        // 倒计时期间状态可能已被其他事件抢占（如到期提醒），只在仍是本卡时回落
        if case .prepReminder(let current, _) = store.islandState, current.id == todo.id {
            store.dismiss()
        }
    }
}
