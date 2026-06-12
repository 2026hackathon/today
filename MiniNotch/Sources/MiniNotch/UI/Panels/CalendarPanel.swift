import SwiftUI

// ============================================================
// CalendarPanel —— 日历独立页签（按日期分组展示多日会议）。
// 每个日期段带「日号徽章 + 相对日期」头部，今天的段落用
// surface 卡片高亮并自动滚动定位；行复用 MeetingRow。
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
        VStack(alignment: .leading, spacing: 10) {
            overviewRow
            ForEach(store.meetingsByDate, id: \.date) { entry in
                DateSection(date: entry.date, meetings: entry.meetings)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 概览行（对齐 Today 的问候行样式）：日程/提醒分开计数
    private var overviewRow: some View {
        let eventCount = store.meetings.filter { !$0.isReminder }.count
        let reminderCount = store.meetings.count - eventCount
        var parts: [String] = []
        if eventCount > 0 { parts.append("\(eventCount) 场日程") }
        if reminderCount > 0 { parts.append("\(reminderCount) 个提醒") }
        return Text(parts.joined(separator: " · "))
            .font(DS.Fonts.button)
            .foregroundStyle(DS.Colors.text2)
            .padding(.horizontal, 10)
            .padding(.top, 4)
    }

    // MARK: - 空态（未授权时引导授权）

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.calendarAuthState == .authorized
                  ? "calendar" : "calendar.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(DS.Colors.text3)
            switch store.calendarAuthState {
            case .authorized:
                emptyText(title: "暂无日程", detail: "手动创建或账户同步的日程和提醒会显示在这里")
            case .needsRequest:
                emptyText(title: "尚未授权访问日历", detail: "授权后日程和提醒会显示在这里，并随苹果日历自动同步")
                authButton("允许访问日历")
            case .denied:
                emptyText(title: "日历访问已被拒绝", detail: "请在 系统设置 → 隐私与安全性 → 日历 中允许本应用")
                authButton("前往系统设置")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }

    @ViewBuilder
    private func emptyText(title: String, detail: String) -> some View {
        Text(title)
            .font(DS.Fonts.button)
            .foregroundStyle(DS.Colors.text3)
        Text(detail)
            .font(DS.Fonts.meta)
            .foregroundStyle(DS.Colors.text3)
    }

    private func authButton(_ title: String) -> some View {
        Button(title) { store.requestCalendarAccess() }
            .font(DS.Fonts.button)
            .foregroundStyle(DS.Colors.accent)
            .buttonStyle(.plain)
            .padding(.top, 4)
    }
}

// MARK: - 日期段落（日号徽章头部 + 该日 MeetingRow 列表）

private struct DateSection: View {
    let date: Date
    let meetings: [Meeting]

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(meetings) { meeting in
                MeetingRow(meeting: meeting)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        // 所有段落同 padding 保证左对齐，仅今天有卡片底色
        .background(
            isToday ? DS.Colors.surface1 : .clear,
            in: RoundedRectangle(cornerRadius: DS.Radius.l)
        )
        .id(date) // ScrollViewReader 定位用
    }

    private var header: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text(relativeLabel)
                    .font(DS.Fonts.button)
                    .foregroundStyle(isToday ? DS.Colors.accent : DS.Colors.text1)
                Text(fullLabel)
                    .font(DS.Fonts.tag)
                    .foregroundStyle(DS.Colors.text3)
            }
            Spacer(minLength: 0)
            Text("\(meetings.count) 项")
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
        }
        .padding(.bottom, 4)
    }

    /// 第一行：今天/昨天/明天/周X
    private var relativeLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        if cal.isDateInTomorrow(date) { return "明天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    /// 第二行：M月d日（今天/昨天/明天 时补充周X，避免与第一行的周X重复）
    private var fullLabel: String {
        let cal = Calendar.current
        let isRelative = cal.isDateInToday(date) || cal.isDateInYesterday(date) || cal.isDateInTomorrow(date)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = isRelative ? "M月d日 EEE" : "M月d日"
        return f.string(from: date)
    }
}
