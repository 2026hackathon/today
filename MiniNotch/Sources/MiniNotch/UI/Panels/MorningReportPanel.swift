import AppKit
import SwiftUI

// ============================================================
// MorningReportPanel —— 晨报（prototype `morning` 状态，460×540）。
// text 非空 → Markdown 风格分段渲染 AI 文本；
// text 为空 → 用 store 数据渲染结构化版本（降级路径）。
// 本文件同时提供报告类共享组件：PanelReportSection / PanelReportText / PanelButton。
// ============================================================

struct MorningReportPanel: View {
    let text: String
    @EnvironmentObject var store: AppStore

    var body: some View {
        PanelScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if text.isEmpty {
                    structuredBody
                } else {
                    PanelReportText(text: text)
                }

                actionRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        .padding(.top, 36) // 摄像头区留位
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Colors.gold)
                Text("早上好，今日待办梳理")
                    .font(DS.Fonts.cardTitle)
                    .foregroundStyle(DS.Colors.text1)
            }
            Text(PanelFormat.fullDate())
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text3)
        }
        .padding(.bottom, 14)
    }

    // MARK: - 结构化版本（text 为空时）

    /// 优先处理 = 高优先级前 2 条
    private var priorityItems: [Todo] {
        Array(store.pendingTodos.filter { $0.priority == .high }.prefix(2))
    }

    private var structuredBody: some View {
        let priorityIDs = Set(priorityItems.map(\.id))
        let personals = store.personalTodos.filter { !priorityIDs.contains($0.id) }
        let jiras = store.workItems

        return VStack(alignment: .leading, spacing: 12) {
            if !priorityItems.isEmpty {
                PanelReportSection(title: "优先处理 · \(priorityItems.count)", color: DS.Colors.alert) {
                    ForEach(priorityItems) { todo in
                        HStack(spacing: 8) {
                            PanelPriorityTag(priority: todo.priority)
                            Text(deadlineTitle(todo))
                                .font(DS.Fonts.button)
                                .foregroundStyle(DS.Colors.text1)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            if !store.todayMeetings.isEmpty {
                PanelReportSection(title: "今日会议 · \(store.todayMeetings.count)") {
                    ForEach(store.todayMeetings) { meeting in
                        HStack(spacing: 8) {
                            Text("\(PanelFormat.hm(meeting.start))-\(PanelFormat.hm(meeting.end))")
                                .font(DS.Fonts.compactSide)
                                .foregroundStyle(DS.Colors.text2)
                            Text(meeting.title)
                                .font(DS.Fonts.button)
                                .foregroundStyle(DS.Colors.text1)
                            if let platform = meeting.platform {
                                Text(platform.label).dsTag()
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            if !personals.isEmpty {
                PanelReportSection(title: "个人 TODO · \(personals.count)") {
                    ForEach(personals) { todo in
                        Text(todo.title)
                            .font(DS.Fonts.button)
                            .foregroundStyle(DS.Colors.text1)
                            .padding(.vertical, 3)
                    }
                }
            }

            if !jiras.isEmpty {
                PanelReportSection(title: "工作项 · \(jiras.count)") {
                    ForEach(jiras) { item in
                        Text(workItemLine(item))
                            .font(DS.Fonts.button)
                            .foregroundStyle(DS.Colors.text1)
                            .padding(.vertical, 3)
                    }
                }
            }

            // TODO: B 接 AIService 后替换为真实建议
            PanelAISuggestion(text: "建议: 上午专注处理优先项，14:00 后处理 Jira tickets。")
        }
    }

    // MARK: - 按钮行

    private var actionRow: some View {
        HStack(spacing: 6) {
            PanelButton(title: "复制为文本") { copyToPasteboard() }
            PanelButton(title: "开始工作", kind: .primary) { store.dismiss() }
        }
        .padding(.top, 14)
    }

    // MARK: - 文本生成

    private func deadlineTitle(_ todo: Todo) -> String {
        if let due = todo.dueDate {
            return "\(todo.title)（截止 \(PanelFormat.due(due))）"
        }
        return todo.title
    }

    private func workItemLine(_ item: WorkItem) -> String {
        let status = item.status.map { " (\($0))" } ?? ""
        return "\(item.key) \(item.title)\(status)"
    }

    private func reportMarkdown() -> String {
        if !text.isEmpty { return text }
        var lines = ["# 早报 \(PanelFormat.fullDate())", ""]
        if !priorityItems.isEmpty {
            lines.append("## 优先处理")
            for todo in priorityItems { lines.append("- [高] \(deadlineTitle(todo))") }
            lines.append("")
        }
        if !store.todayMeetings.isEmpty {
            lines.append("## 今日会议")
            for m in store.todayMeetings {
                let platform = m.platform.map { "（\($0.label)）" } ?? ""
                lines.append("- \(PanelFormat.hm(m.start))-\(PanelFormat.hm(m.end)) \(m.title)\(platform)")
            }
            lines.append("")
        }
        let priorityIDs = Set(priorityItems.map(\.id))
        let personals = store.personalTodos.filter { !priorityIDs.contains($0.id) }
        if !personals.isEmpty {
            lines.append("## 个人 TODO")
            for todo in personals { lines.append("- \(todo.title)") }
            lines.append("")
        }
        let jiras = store.workItems
        if !jiras.isEmpty {
            lines.append("## 工作项")
            for item in jiras { lines.append("- \(workItemLine(item))") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(reportMarkdown(), forType: .string)
    }
}

// ============================================================
// 报告类共享组件（晨报/晚报共用）
// ============================================================

// MARK: - 报告 section（10pt 大写标题 + 内容）

struct PanelReportSection<Content: View>: View {
    let title: String
    var color: Color = DS.Colors.text3
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Fonts.sectionTitle)
                .foregroundStyle(color)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.bottom, 6)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Markdown 风格分段渲染（AI 报告文本）

struct PanelReportText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()),
                    id: \.offset) { _, raw in
                line(String(raw))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func line(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 4)
        } else if trimmed.hasPrefix("#") {
            Text(String(trimmed.drop(while: { $0 == "#" || $0 == " " })))
                .font(DS.Fonts.sectionTitle)
                .foregroundStyle(DS.Colors.text3)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.top, 6)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
            HStack(alignment: .top, spacing: 6) {
                Text("·")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text3)
                Text(inlineMarkdown(String(trimmed.dropFirst(2))))
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text1)
                    .lineSpacing(3)
            }
        } else {
            Text(inlineMarkdown(trimmed))
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .lineSpacing(3)
        }
    }

    /// 行内 **加粗** / `code` 等用系统 Markdown 解析，失败则原样显示
    private func inlineMarkdown(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string)) ?? AttributedString(string)
    }
}

// MARK: - 报告按钮（.btn / .btn.primary）

struct PanelButton: View {
    enum Kind { case normal, primary, disabled }

    let title: String
    var kind: Kind = .normal
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(kind == .primary ? DS.Fonts.button.weight(.semibold) : DS.Fonts.button)
                .foregroundStyle(kind == .primary ? DS.Colors.islandBG : DS.Colors.text1)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .strokeBorder(kind == .primary ? Color.clear : DS.Colors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(kind == .disabled)
        .opacity(kind == .disabled ? 0.4 : 1)
    }

    private var background: Color {
        switch kind {
        case .primary: hovering ? DS.Colors.text1.opacity(0.88) : DS.Colors.text1
        case .normal, .disabled: hovering ? DS.Colors.surface2 : DS.Colors.surface1
        }
    }
}
