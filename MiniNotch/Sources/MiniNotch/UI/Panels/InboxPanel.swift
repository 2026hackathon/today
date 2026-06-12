import SwiftUI

// ============================================================
// InboxPanel —— 「全部任务」视图（today-focus-redesign）。
// 收纳今日焦点之外的所有未完成项：未来截止的任务 + To Do 状态的 Jira。
// 嵌在 TodayPanel 的 ScrollView 内（tab == .inbox 时渲染）。
// ============================================================

struct InboxPanel: View {
    @EnvironmentObject var store: AppStore

    private var personal: [Todo] { store.inboxTodos.filter { $0.source != .jira } }
    private var jira: [Todo] { store.inboxTodos.filter { $0.source == .jira } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("今日焦点之外的 \(store.inboxTodos.count) 项存货")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 12)

            if store.inboxTodos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.Colors.text3)
                    Text("没有积压，轻装上阵")
                        .font(DS.Fonts.button)
                        .foregroundStyle(DS.Colors.text3)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            }

            if !personal.isEmpty {
                PanelSectionTitle(title: "个人任务", count: personal.count)
                ForEach(personal) { todo in
                    TaskRow(todo: todo)
                }
            }

            if !personal.isEmpty && !jira.isEmpty {
                PanelDivider()
            }

            if !jira.isEmpty {
                PanelSectionTitle(title: "Jira Tickets", count: jira.count)
                ForEach(jira) { todo in
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
