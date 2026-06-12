import SwiftUI

// ============================================================
// HoverPreview —— 悬停预览（NEXT UP 前 3 条）。
// 对应 prototype.html STATES.hover。
// ============================================================

struct HoverPreview: View {
    @EnvironmentObject var store: AppStore

    /// 个人 Todo 在前、Jira 在后，取前 3 条
    private var topTodos: [Todo] {
        Array((store.personalTodos + store.jiraTodos).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NEXT UP")
                .font(DS.Fonts.sectionTitle)
                .kerning(0.8)
                .foregroundStyle(DS.Colors.text3)
                .padding(.top, 4)
                .padding(.bottom, 8)

            if topTodos.isEmpty {
                Text("暂无待办")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text3)
                    .padding(.vertical, 5)
            } else {
                ForEach(topTodos) { todo in
                    row(todo)
                }
            }

            Rectangle()
                .fill(DS.Colors.border)
                .frame(height: 1)
                .padding(.top, 8)

            Text("⌘⇧L 展开全部")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DS.Colors.text3)
                .padding(.top, 8)
        }
        .padding(.top, 36)   // 摄像头区
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - 单条（优先级 tag + 标题 + 截止）

    private func row(_ todo: Todo) -> some View {
        HStack(spacing: 8) {
            Text(todo.priority.label)
                .dsTag(tagColor(todo.priority), bg: tagBackground(todo.priority))

            Text(rowTitle(todo))
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text1)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if let due = todo.dueDate {
                Text(due.dsShortLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Colors.text3)
            }
        }
        .padding(.vertical, 5)
    }

    /// Jira 任务带 key 前缀（prototype: "MD-1024 修复登录 bug"）
    private func rowTitle(_ todo: Todo) -> String {
        if let key = todo.jiraKey {
            return "\(key) \(todo.title)"
        }
        return todo.title
    }

    private func tagColor(_ p: Priority) -> Color {
        switch p {
        case .high: DS.Colors.alert
        case .medium: DS.Colors.text2
        case .low: DS.Colors.text3
        }
    }

    private func tagBackground(_ p: Priority) -> Color {
        p == .high ? DS.Colors.alertSoft : DS.Colors.surface1
    }
}
