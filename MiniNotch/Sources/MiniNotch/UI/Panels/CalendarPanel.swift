import SwiftUI

// ============================================================
// CalendarPanel —— 日历独立页签（按日期分组展示多日会议）。
// 样式对齐 Today/Inbox：PanelScrollView + PanelSectionTitle +
// MeetingRow + PanelDivider，不另造时间轴样式。
// ============================================================

struct CalendarPanel: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            PanelTabBar(current: .calendar)
            ScrollViewReader { proxy in
                PanelScrollView {
                    if store.meetingsByDate.isEmpty {
                        emptyState
                    } else {
                        groupedList
                            .onAppear {
                                // 滚动到今日段落
                                if let todayEntry = store.meetingsByDate.first(where: { Calendar.current.isDateInToday($0.date) }) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo(todayEntry.date, anchor: .top)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .padding(.top, 36) // 摄像头区留位
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 分组内容

    private var groupedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 概览行（对齐 Today 的问候行样式）
            Text("近 30 天 \(store.meetings.count) 场会议")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 12)

            // 按日期分组
            ForEach(Array(store.meetingsByDate.enumerated()), id: \.element.date) { index, entry in
                if index > 0 {
                    PanelDivider()
                }
                DateSection(date: entry.date, meetings: entry.meetings)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 24))
                .foregroundStyle(DS.Colors.text3)
            Text("暂无会议")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text3)
            Text("苹果日历中的会议会显示在这里")
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text3)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }
}

// MARK: - 日期段落（PanelSectionTitle + 该日 MeetingRow 列表）

private struct DateSection: View {
    let date: Date
    let meetings: [Meeting]

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionTitle(
                title: sectionTitle,
                count: meetings.count,
                color: isToday ? DS.Colors.accent : DS.Colors.text3
            )
            ForEach(meetings) { meeting in
                MeetingRow(meeting: meeting)
            }
        }
        .id(date) // ScrollViewReader 定位用
    }

    private var sectionTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "M月d日"
            return "今天 \(f.string(from: date))"
        }
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        if cal.isDate(cal.startOfDay(for: date), inSameDayAs: cal.startOfDay(for: yesterday)) {
            let f = DateFormatter()
            f.dateFormat = "M月d日"
            return "昨天 \(f.string(from: date))"
        }
        // 其他日期：M月d日 周X
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"
        return f.string(from: date)
    }
}
