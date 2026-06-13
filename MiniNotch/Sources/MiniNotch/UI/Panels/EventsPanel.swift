import SwiftUI

// ============================================================
// EventsPanel —— 「日历事件」页签（concept-tabs）。
// 纯事件议程：会议 / 节假日 / 全天事件（CalendarEvent 概念），不含个人任务，
// 也不含提醒事项（提醒事项属 Todo 概念，在「任务」/「Calendar」里）。
// 按日期分组，今天高亮并自动滚动定位。完整事件+任务时间线在 Calendar 页签。
// ============================================================

struct EventsPanel: View {
    @EnvironmentObject var store: AppStore

    /// 纯事件按日期分组（排除提醒事项）
    private var groups: [(date: Date, events: [Meeting])] {
        store.meetingsByDate
            .map { (date: $0.date, events: $0.meetings.filter { !$0.isReminder }) }
            .filter { !$0.events.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelTabBar(current: .events)
            ScrollViewReader { proxy in
                PanelScrollView {
                    if groups.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            overviewRow
                            ForEach(groups, id: \.date) { group in
                                EventDateSection(date: group.date, events: group.events)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear {
                            if let today = groups.first(where: { Calendar.current.isDateInToday($0.date) }) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(today.date, anchor: .top)
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

    private var overviewRow: some View {
        let count = groups.reduce(0) { $0 + $1.events.count }
        return Text(count > 0 ? "\(count) 场日程" : "暂无日程")
            .font(DS.Fonts.button)
            .foregroundStyle(DS.Colors.text2)
            .padding(.horizontal, 10)
            .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.calendarAuthState == .authorized
                  ? "calendar" : "calendar.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(DS.Colors.text3)
            switch store.calendarAuthState {
            case .authorized:
                Text("暂无日程")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text3)
                Text("账户同步的会议、节假日会显示在这里")
                    .font(DS.Fonts.meta)
                    .foregroundStyle(DS.Colors.text3)
            case .needsRequest:
                Text("尚未授权访问日历")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text3)
                Button("允许访问日历") { store.requestCalendarAccess() }
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.accent)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            case .denied:
                Text("日历访问已被拒绝")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text3)
                Text("请在 系统设置 → 隐私与安全性 → 日历 中允许本应用")
                    .font(DS.Fonts.meta)
                    .foregroundStyle(DS.Colors.text3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }
}

// MARK: - 日期段落（纯事件）

private struct EventDateSection: View {
    let date: Date
    let events: [Meeting]
    @EnvironmentObject var store: AppStore

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(events) { meeting in
                MeetingRow(meeting: meeting, isCompleted: store.isMeetingCompleted(meeting))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            isToday ? DS.Colors.surface1 : .clear,
            in: RoundedRectangle(cornerRadius: DS.Radius.l)
        )
        .id(date)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(relativeLabel)
                .font(DS.Fonts.button)
                .foregroundStyle(isToday ? DS.Colors.accent : DS.Colors.text1)
            Text(fullLabel)
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }

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

    private var fullLabel: String {
        let cal = Calendar.current
        let isRelative = cal.isDateInToday(date) || cal.isDateInYesterday(date) || cal.isDateInTomorrow(date)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = isRelative ? "M月d日 EEE" : "M月d日"
        return f.string(from: date)
    }
}
