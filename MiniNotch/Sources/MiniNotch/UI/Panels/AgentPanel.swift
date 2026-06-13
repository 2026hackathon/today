import SwiftUI

// ============================================================
// AgentPanel —— Agent tab：Claude Code / opencode 会话一览。
// 需处理的（等待确认/已完成）在前，运行中在后。点击行跳转对应终端 session。
// 嵌在 TodayPanel 的 ScrollView 内（tab == .agent 时渲染）。
// ============================================================

struct AgentPanel: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 概览行
            Text(summary)
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 12)

            if store.agentSessions.isEmpty {
                emptyState
            } else {
                ForEach(store.sortedAgentSessions) { session in
                    AgentSessionRow(session: session) { store.jumpToAgent(session) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: String {
        let a = store.activeAgentCount, w = store.waitingAgentCount
        if store.agentSessions.isEmpty { return "暂无 agent 会话" }
        var parts: [String] = []
        if a > 0 { parts.append("\(a) 个运行中") }
        if w > 0 { parts.append("\(w) 个待处理") }
        return parts.isEmpty ? "\(store.agentSessions.count) 个会话" : parts.joined(separator: "、")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 24))
                .foregroundStyle(DS.Colors.text3)
            Text("暂无 agent 会话")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text3)
            Text("在 Claude Code / opencode 里开会话即可显示\n（菜单栏 Debug 可安装 hook / 插件）")
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text3)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

// MARK: - 会话行

struct AgentSessionRow: View {
    let session: AgentSession
    let onJump: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 状态点 + 图标
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.agent)
                        .font(DS.Fonts.todoTitle)
                        .foregroundStyle(DS.Colors.text1)
                    if let project = session.project {
                        Text(project).dsTag()
                    }
                }
                HStack(spacing: 6) {
                    Text(stateLabel)
                        .font(DS.Fonts.meta)
                        .foregroundStyle(color)
                    if session.state == .waiting, let msg = session.message, !msg.isEmpty {
                        Text(msg)
                            .font(DS.Fonts.meta)
                            .foregroundStyle(DS.Colors.text3)
                            .lineLimit(1)
                    }
                    Text("· \(relativeTime)")
                        .font(DS.Fonts.meta)
                        .foregroundStyle(DS.Colors.text3)
                }
            }
            Spacer(minLength: 0)
            // 行尾跳转箭头（hover 才显示）
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.text3)
                .opacity(hovering ? 1 : 0)
                .padding(.top, 2)
        }
        .padding(8)
        .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m))
        .onTapGesture { onJump() }
        .onHover { hovering = $0 }
    }

    private var icon: String {
        switch session.state {
        case .working: "cpu"
        case .waiting: "bell.fill"
        case .replied: "checkmark.seal.fill"
        case .ended: "xmark.circle"
        }
    }

    private var color: Color {
        switch session.state {
        case .working: DS.Colors.accent
        case .waiting: DS.Colors.warning
        case .replied: DS.Colors.success
        case .ended: DS.Colors.text3
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .working: "运行中"
        case .waiting: "等待确认"
        case .replied: "已完成 · 等你 review"
        case .ended: "已结束"
        }
    }

    private var relativeTime: String {
        let s = Int(Date().timeIntervalSince(session.updatedAt))
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(s / 60) 分钟前" }
        return "\(s / 3600) 小时前"
    }
}
