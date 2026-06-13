import AppKit
import SwiftUI

// ============================================================
// AgentLandedCard —— agent 一轮完成通知卡（agent-landed-jump spec）。
// 克隆 JiraLandedCard 的「降落 + 倒计时 + 自动收回」：
//   - 纯通知，5s 倒计时后收入岛体，悬停暂停
//   - 点击卡片 → 跳转对应终端 session（onJump 注入，由 AgentSessionService 执行）
// ============================================================

struct AgentLandedCard: View {
    let session: AgentSession
    /// 点击跳转（AppDelegate 注入 → AgentSessionService.jumpTo）
    let onJump: (AgentSession) -> Void
    @EnvironmentObject var store: AppStore

    private static let duration: Double = 5.0

    @State private var remaining = AgentLandedCard.duration
    @State private var hovering = false
    @State private var collecting = false

    /// agent 完成用绿色（success），与 Jira 蓝 / GitHub 紫区分
    private var accent: Color { DS.Colors.success }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            titleBlock
            metaRow
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { countdownBar }
        .scaleEffect(collecting ? 0.05 : 1, anchor: .top)
        .opacity(collecting ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { jumpAndCollect() }
        .onHover { hovering = $0 }
        .task(id: session.id) { await runCountdown() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text("\(session.agent) 已完成")
                .font(DS.Fonts.meta.weight(.medium))
                .foregroundStyle(DS.Colors.text2)
            Spacer(minLength: 0)
            if let project = session.project {
                Text(project).dsTag()
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
            Text("等你 review / 下一步")
                .font(DS.Fonts.cardTitle)
                .foregroundStyle(DS.Colors.text1)
                .lineLimit(2)
        }
        .padding(.bottom, 10)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            if let term = session.terminal?.program, !term.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "terminal.fill").font(.system(size: 8))
                    Text(Self.termLabel(term))
                }
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text2)
            }
            Spacer(minLength: 0)
            Text(session.terminal != nil ? "点击跳转终端" : "点击打开目录")
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.bottom, 6)
    }

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

    /// TERM_PROGRAM → 友好名
    private static func termLabel(_ raw: String) -> String {
        switch raw {
        case "WarpTerminal": "Warp"
        case "iTerm.app": "iTerm"
        case "Apple_Terminal": "Terminal"
        case "vscode": "VS Code"
        default: raw
        }
    }

    private func runCountdown() async {
        while remaining > 0 {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            if !hovering { remaining = max(0, remaining - 0.05) }
        }
        await collect()
    }

    private func jumpAndCollect() {
        onJump(session)
        Task { await collect() }
    }

    private func collect() async {
        guard !collecting else { return }
        withAnimation(.easeIn(duration: 0.22)) { collecting = true }
        try? await Task.sleep(for: .milliseconds(220))
        if case .agentLanded(let current) = store.islandState, current.id == session.id {
            store.dismiss()
        }
    }
}
