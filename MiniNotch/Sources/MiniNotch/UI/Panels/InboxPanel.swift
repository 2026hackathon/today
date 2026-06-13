import SwiftUI

// ============================================================
// InboxPanel —— 「Later」视图（later-into-calendar）。
// 只收纳今日焦点之外的「外部来源」待办：To Do 状态 Jira / 未进焦点的 GitHub。
// 个人任务已统一收敛到 Calendar 页签，不在此展示。
// 嵌在 TodayPanel 的 ScrollView 内（tab == .inbox 时渲染）。
// ============================================================

struct InboxPanel: View {
    @EnvironmentObject var store: AppStore

    private var jira: [WorkItem] { store.inboxWorkItems.filter { $0.source == .jira } }
    private var github: [WorkItem] { store.inboxWorkItems.filter { $0.source == .github } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("待处理的外部事项 \(store.inboxWorkItems.count) 项")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 12)

            if store.inboxWorkItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.Colors.text3)
                    Text("没有积压，轻装上阵")
                        .font(DS.Fonts.button)
                        .foregroundStyle(DS.Colors.text3)
                    Text("个人任务都在「日历」页签")
                        .font(DS.Fonts.meta)
                        .foregroundStyle(DS.Colors.text3)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            }

            if !jira.isEmpty {
                PanelSectionTitle(title: "Jira Tickets", count: jira.count)
                ForEach(jira) { item in
                    WorkItemRow(item: item)
                }
            }

            if !jira.isEmpty && !github.isEmpty {
                PanelDivider()
            }

            if !github.isEmpty {
                PanelSectionTitle(title: "GitHub", count: github.count)
                ForEach(github) { item in
                    WorkItemRow(item: item)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
