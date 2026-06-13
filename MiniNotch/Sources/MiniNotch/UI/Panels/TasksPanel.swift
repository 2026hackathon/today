import SwiftUI

// ============================================================
// TasksPanel —— 「任务」页签（concept-tabs）。
// 全部未完成个人任务的纯列表（可勾选完成），区别于 Today（仅今日）
// 与 Calendar（按时间线）。已超期高亮在前，其余按优先级/时间排。
// 嵌在 TodayPanel 的 ScrollView 内（tab == .tasks 时渲染）。
// ============================================================

struct TasksPanel: View {
    @EnvironmentObject var store: AppStore

    private var overdue: [Todo] { store.overdueTodos }
    private var rest: [Todo] {
        let overdueIDs = Set(overdue.map(\.id))
        return store.personalTodos.filter { !overdueIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.personalTodos.isEmpty ? "没有待办，轻装上阵" : "未完成 \(store.personalTodos.count) 项")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 12)

            if store.personalTodos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.Colors.text3)
                    Text("全部完成")
                        .font(DS.Fonts.button)
                        .foregroundStyle(DS.Colors.text3)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }

            if !overdue.isEmpty {
                PanelSectionTitle(title: "已超期", count: overdue.count, color: DS.Colors.alert)
                ForEach(overdue) { todo in
                    TaskRow(todo: todo)
                }
            }

            if !overdue.isEmpty && !rest.isEmpty {
                PanelDivider()
            }

            if !rest.isEmpty {
                PanelSectionTitle(title: "全部任务", count: rest.count)
                ForEach(rest) { todo in
                    TaskRow(todo: todo)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
