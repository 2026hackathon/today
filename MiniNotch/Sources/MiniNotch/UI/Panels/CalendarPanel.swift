import SwiftUI

// ============================================================
// CalendarPanel —— 日历独立页签（按日期分组的统一时间线）。
// later-into-calendar：除苹果来源日程/提醒外，本地个人任务也并入时间线——
// 有截止时间的按 dueDate 归入对应日期并按时间排序，无截止的落今天的「无固定时间」区。
// 每个日期段带「相对日期 + 具体日期」头部，今天的段落高亮并自动滚动定位。
// ============================================================

struct CalendarPanel: View {
    @EnvironmentObject var store: AppStore

    /// 时间线一行：日历事件/提醒，或本地个人任务（带截止时间）
    enum TimelineItem: Identifiable {
        case meeting(Meeting)
        case todo(Todo)

        var id: String {
            switch self {
            case .meeting(let m): "m-\(m.id)"
            case .todo(let t): "t-\(t.id)"
            }
        }

        var sortKey: Date {
            switch self {
            case .meeting(let m): m.start
            case .todo(let t): t.effectiveDue ?? .distantFuture
            }
        }
    }

    /// 一个日期分组：当天的时间线项（已按时间排序）+ 今天专属的无固定时间个人任务
    struct DayGroup: Identifiable {
        let date: Date
        let timed: [TimelineItem]
        let untimed: [Todo]
        var id: Date { date }
    }

    /// 合并 meetings 与本地个人任务为按日期分组的时间线
    private var dayGroups: [DayGroup] {
        let cal = Calendar.current
        var timedByDay: [Date: [TimelineItem]] = [:]

        for entry in store.meetingsByDate {
            timedByDay[entry.date, default: []].append(contentsOf: entry.meetings.map(TimelineItem.meeting))
        }

        var untimed: [Todo] = []
        for todo in store.calendarPersonalTodos {
            if let due = todo.effectiveDue {
                let day = cal.startOfDay(for: due)
                timedByDay[day, default: []].append(.todo(todo))
            } else {
                untimed.append(todo)
            }
        }

        // 无固定时间任务统一挂在今天分组下；若今天本无任何项，仍建一个空分组承载
        let today = cal.startOfDay(for: Date())
        if !untimed.isEmpty, timedByDay[today] == nil {
            timedByDay[today] = []
        }

        return timedByDay.keys.sorted().map { day in
            DayGroup(
                date: day,
                timed: (timedByDay[day] ?? []).sorted { $0.sortKey < $1.sortKey },
                untimed: cal.isDate(day, inSameDayAs: today) ? untimed : []
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelTabBar(current: .calendar)
            ScrollViewReader { proxy in
                PanelScrollView {
                    let groups = dayGroups
                    if groups.isEmpty {
                        emptyState
                    } else {
                        groupedList(groups)
                            .onAppear {
                                // 滚动到今日段落
                                if let todayEntry = groups.first(where: { Calendar.current.isDateInToday($0.date) }) {
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

    private func groupedList(_ groups: [DayGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            overviewRow
            ForEach(groups) { group in
                DateSection(date: group.date, timed: group.timed, untimed: group.untimed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 概览行（对齐 Today 的问候行样式）：日程/提醒/个人任务分开计数
    private var overviewRow: some View {
        let eventCount = store.meetings.filter { !$0.isReminder }.count
        let reminderCount = store.meetings.count - eventCount
        let todoCount = store.calendarPersonalTodos.count
        var parts: [String] = []
        if eventCount > 0 { parts.append("\(eventCount) 场日程") }
        if reminderCount > 0 { parts.append("\(reminderCount) 个提醒") }
        if todoCount > 0 { parts.append("\(todoCount) 个任务") }
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
                emptyText(title: "暂无日程", detail: "手动创建的任务、账户同步的日程和提醒会显示在这里")
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

// MARK: - 日期段落（日号徽章头部 + 该日时间线 + 无固定时间任务）

private struct DateSection: View {
    let date: Date
    let timed: [CalendarPanel.TimelineItem]
    let untimed: [Todo]
    @EnvironmentObject var store: AppStore

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ForEach(timed) { item in
                switch item {
                case .meeting(let meeting):
                    MeetingRow(meeting: meeting, isCompleted: store.isMeetingCompleted(meeting))
                case .todo(let todo):
                    TaskRow(todo: todo)
                }
            }
            if !untimed.isEmpty {
                PanelMiniDividerLabel(text: "无固定时间")
                ForEach(untimed) { todo in
                    TaskRow(todo: todo)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        // 所有段落同 padding 保证左对齐，仅今天有卡片底色
        .background(
            isToday ? DS.Colors.surface1 : .clear,
            in: RoundedRectangle(cornerRadius: DS.Radius.l)
        )
        // 过去日期段落整体降权
        .opacity(date < Calendar.current.startOfDay(for: Date()) ? 0.5 : 1)
        .id(date) // ScrollViewReader 定位用
    }

    private var header: some View {
        // 单行扫读：相对日期（今天/明天/周X）作锚点 + 具体日期次级灰字
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
