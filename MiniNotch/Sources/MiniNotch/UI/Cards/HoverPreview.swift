import SwiftUI

// ============================================================
// HoverPreview —— 悬停预览（NEXT UP 前 3 条）。
// 对应 prototype.html STATES.hover。
// ============================================================

struct HoverPreview: View {
    @EnvironmentObject var store: AppStore

    /// 个人 Todo 前 3 条（外部工作项不挤这块小预览，完整在 Today/工作项）
    private var topTodos: [Todo] {
        Array(store.personalTodos.prefix(3))
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
        // 摄像头避让由 IslandRootView 路由层统一加（notchHeight+4），这里不再叠加
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    // MARK: - 单条（优先级 tag + 标题 + 截止）

    private func row(_ todo: Todo) -> some View {
        HStack(spacing: 8) {
            Text(todo.priority.label)
                .dsTag(tagColor(todo.priority), bg: tagBackground(todo.priority))

            Text(todo.title)
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

    private func tagColor(_ p: Priority) -> Color { DS.priorityTagFG(p) }
    private func tagBackground(_ p: Priority) -> Color { DS.priorityTagBG(p) }
}
