import AppKit
import SwiftUI

// ============================================================
// EveningReportPanel —— 晚报（PRD 8.7，与晨报对称，460×540）。
// text 非空 → Markdown 风格分段渲染 AI 文本；
// text 为空 → 用 store 数据渲染结构化版本（降级路径）。
// ============================================================

struct EveningReportPanel: View {
    let text: String
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
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
        .scrollIndicators(.hidden)
        .padding(.top, 36) // 摄像头区留位
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Colors.accent)
                Text("晚上好，今日工作复盘")
                    .font(DS.Fonts.cardTitle)
                    .foregroundStyle(DS.Colors.text1)
            }
            Text(PanelFormat.fullDate())
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text3)
        }
        .padding(.bottom, 14)
    }

    // MARK: - 派生数据

    /// 延期到明天 = 有 snoozedUntil 的未完成条目
    private var snoozedItems: [Todo] {
        store.pendingTodos.filter { $0.snoozedUntil != nil }
    }

    /// 逾期风险 = 明天截止的高优条目 / snooze 过 2 次以上的条目
    private var riskItems: [Todo] {
        store.pendingTodos.filter { todo in
            if todo.snoozeCount >= 2 { return true }
            if let due = todo.dueDate,
               Calendar.current.isDateInTomorrow(due),
               todo.priority == .high { return true }
            return false
        }
    }

    /// 明天到期的待办数（明日预告用）
    private var tomorrowDueCount: Int {
        store.pendingTodos.filter {
            guard let due = $0.dueDate else { return false }
            return Calendar.current.isDateInTomorrow(due)
        }.count
    }

    // MARK: - 结构化版本（text 为空时）

    private var structuredBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 今日完成
            PanelReportSection(title: "今日完成 (\(store.completedToday.count))", color: DS.Colors.success) {
                if store.completedToday.isEmpty {
                    Text("今天还没有完成的任务")
                        .font(DS.Fonts.button)
                        .foregroundStyle(DS.Colors.text3)
                        .padding(.vertical, 3)
                } else {
                    ForEach(store.completedToday) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Colors.success)
                            Text(todo.title)
                                .font(DS.Fonts.button)
                                .foregroundStyle(DS.Colors.text2)
                                .strikethrough(true, color: DS.Colors.text3)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            // 延期到明天
            if !snoozedItems.isEmpty {
                PanelReportSection(title: "延期到明天 · \(snoozedItems.count)") {
                    ForEach(snoozedItems) { todo in
                        HStack(spacing: 8) {
                            Text(todo.title)
                                .font(DS.Fonts.button)
                                .foregroundStyle(DS.Colors.text1)
                            Text("已延期 \(todo.snoozeCount) 次").dsTag()
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            // 今日参加的会议
            if !store.todayMeetings.isEmpty {
                PanelReportSection(title: "今日参加的会议 · \(store.todayMeetings.count)") {
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

            // 逾期风险预警
            if !riskItems.isEmpty {
                PanelReportSection(title: "逾期风险预警 · \(riskItems.count)", color: DS.Colors.alert) {
                    ForEach(riskItems) { todo in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(DS.Colors.alert)
                            Text(riskLine(todo))
                                .font(DS.Fonts.button)
                                .foregroundStyle(DS.Colors.alert)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            // 明日预告 + 建议
            // TODO: B 接 AIService 后替换为真实建议
            PanelAISuggestion(text: tomorrowSuggestion)
        }
    }

    private var tomorrowSuggestion: String {
        "明日预告: 明天有 \(tomorrowDueCount) 个待办到期，共 \(store.pendingCount) 项进行中。建议明早优先处理高优先级与逾期风险条目。"
    }

    private func riskLine(_ todo: Todo) -> String {
        var reasons: [String] = []
        if let due = todo.dueDate, Calendar.current.isDateInTomorrow(due), todo.priority == .high {
            reasons.append("明天 \(PanelFormat.hm(due)) 截止")
        }
        if todo.snoozeCount >= 2 {
            reasons.append("已延期 \(todo.snoozeCount) 次")
        }
        let key = todo.jiraKey.map { "\($0) " } ?? ""
        let suffix = reasons.isEmpty ? "" : "（\(reasons.joined(separator: "，"))）"
        return "\(key)\(todo.title)\(suffix)"
    }

    // MARK: - 按钮行

    private var actionRow: some View {
        HStack(spacing: 6) {
            PanelButton(title: "复制为文本") { copyToPasteboard() }
            // TODO: C 接 PushService 后启用
            PanelButton(title: "发送到微信/飞书", kind: .disabled) {}
            PanelButton(title: "收到", kind: .primary) { store.dismiss() }
        }
        .padding(.top, 14)
    }

    // MARK: - 文本生成

    private func reportMarkdown() -> String {
        if !text.isEmpty { return text }
        var lines = ["# 晚报 \(PanelFormat.fullDate())", ""]
        lines.append("## 今日完成 (\(store.completedToday.count))")
        for todo in store.completedToday { lines.append("- \(todo.title)") }
        lines.append("")
        if !snoozedItems.isEmpty {
            lines.append("## 延期到明天")
            for todo in snoozedItems { lines.append("- \(todo.title)（已延期 \(todo.snoozeCount) 次）") }
            lines.append("")
        }
        if !store.todayMeetings.isEmpty {
            lines.append("## 今日参加的会议")
            for m in store.todayMeetings {
                let platform = m.platform.map { "（\($0.label)）" } ?? ""
                lines.append("- \(PanelFormat.hm(m.start))-\(PanelFormat.hm(m.end)) \(m.title)\(platform)")
            }
            lines.append("")
        }
        if !riskItems.isEmpty {
            lines.append("## 逾期风险预警")
            for todo in riskItems { lines.append("- \(riskLine(todo))") }
            lines.append("")
        }
        lines.append("## 明日预告")
        lines.append(tomorrowSuggestion)
        return lines.joined(separator: "\n")
    }

    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(reportMarkdown(), forType: .string)
    }
}
