import SwiftUI

// ============================================================
// WorkItemPanel —— 「工作项」页签（concept-tabs / work-item spec）。
// 展示全部 Jira ticket / GitHub PR：活跃在前、积压在后，只读跳转。
// 嵌在 TodayPanel 的 ScrollView 内（tab == .workItems 时渲染）。
// ============================================================

struct WorkItemPanel: View {
    @EnvironmentObject var store: AppStore

    private var active: [WorkItem] { store.activeWorkItems }
    private var backlog: [WorkItem] { store.inboxWorkItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary)
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 12)

            if store.workItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.Colors.text3)
                    Text("暂无工作项")
                        .font(DS.Fonts.button)
                        .foregroundStyle(DS.Colors.text3)
                    Text("指派给我的 Jira / 待我处理的 GitHub PR 会显示在这里")
                        .font(DS.Fonts.meta)
                        .foregroundStyle(DS.Colors.text3)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }

            if !active.isEmpty {
                PanelSectionTitle(title: "进行中", count: active.count, color: DS.Colors.accent)
                ForEach(active) { item in
                    WorkItemRow(item: item)
                }
            }

            if !active.isEmpty && !backlog.isEmpty {
                PanelDivider()
            }

            if !backlog.isEmpty {
                PanelSectionTitle(title: "待办池", count: backlog.count)
                ForEach(backlog) { item in
                    WorkItemRow(item: item)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: String {
        if store.workItems.isEmpty { return "暂无工作项" }
        var parts: [String] = []
        if !active.isEmpty { parts.append("\(active.count) 个进行中") }
        if !backlog.isEmpty { parts.append("\(backlog.count) 个待办") }
        return parts.joined(separator: "、")
    }
}
