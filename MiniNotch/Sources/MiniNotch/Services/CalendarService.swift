import Foundation
import EventKit

// ============================================================
// CalendarService —— 今日会议拉取协议 + Mock + EventKit 骨架。
// Owner: C
//
// 接真实现步骤（C）：
// 1. EventKitCalendarService.fetchTodayMeetings 中：
//    requestFullAccessToEvents → predicateForEvents(今日 0 点~24 点) → events(matching:)
// 2. EKEvent → Meeting 映射；会议链接用 extractMeetingLink（已是真实现，直接用）。
// 3. AppDelegate 装配处换 EventKitCalendarService；Info.plist 需加
//    NSCalendarsFullAccessUsageDescription。保留 MockCalendarService（Demo 兜底）。
// ============================================================

enum CalendarServiceError: Error {
    /// 真实现尚未接入
    case notImplemented
    /// 用户拒绝日历权限
    case accessDenied
}

@MainActor
protocol CalendarService: AnyObject {
    /// 查询指定日期范围内的所有会议和提醒事项（按 start 升序由实现方保证）
    func fetchMeetings(in range: ClosedRange<Date>) async throws -> [Meeting]
}

/// 协议默认扩展：便捷方法 fetchTodayMeetings() 委托给 fetchMeetings(in: .today)
@MainActor
extension CalendarService {
    func fetchTodayMeetings() async throws -> [Meeting] {
        try await fetchMeetings(in: .today)
    }
}

/// 同步窗口常量 + 日期范围便捷构造
enum CalendarSyncConfig {
    /// 同步窗口：过去天数（含今天共 syncDaysPast+1 天）
    static let syncDaysPast = 29
    /// 同步窗口：未来天数
    static let syncDaysFuture = 6

    /// 默认同步范围：[today - syncDaysPast, today + syncDaysFuture + 1)
    static func defaultRange() -> ClosedRange<Date> {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let lower = cal.date(byAdding: .day, value: -syncDaysPast, to: todayStart)!
        let upper = cal.date(byAdding: .day, value: syncDaysFuture + 1, to: todayStart)!
        return lower...upper
    }
}

/// ClosedRange<Date> 便捷扩展
extension ClosedRange where Bound == Date {
    /// 今日范围：[startOfDay(today), startOfDay(today+1))
    static var today: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return start...end
    }
}

// MARK: - Mock 实现（今日 2 场会议，与 prototype 一致 —— integrations spec）

@MainActor
final class MockCalendarService: CalendarService {

    init() {}

    func fetchMeetings(in range: ClosedRange<Date>) async throws -> [Meeting] {
        try? await Task.sleep(for: .seconds(0.2)) // 模拟读取
        // 生成覆盖请求范围的演示数据（每天 1-2 场会议）
        let cal = Calendar.current
        var results: [Meeting] = []
        var day = cal.startOfDay(for: range.lowerBound)
        let end = range.upperBound
        var dayIndex = 0
        while day < end {
            // 每天生成 1-2 场会议（按天索引交替）
            let count = dayIndex % 2 == 0 ? 2 : 1
            for i in 0..<count {
                let hour = 10 + i * 4 // 10:00, 14:00
                let start = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                let duration: TimeInterval = i == 0 ? 3600 : 1800
                results.append(Meeting(
                    title: i == 0 ? "产品评审" : "周会",
                    start: start,
                    end: start.addingTimeInterval(duration),
                    link: i == 0 ? URL(string: "https://zoom.us/j/123456789") : URL(string: "https://meeting.tencent.com/dm/abc"),
                    platform: i == 0 ? .zoom : .tencent,
                    attendees: i == 0 ? ["陈昊", "林嘉"] : ["全员"],
                    calendarName: "工作"
                ))
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
            dayIndex += 1
        }
        return results.sorted { $0.start < $1.start }
    }
}

// MARK: - EventKit 真实现（事件驱动 + 拉取）

@MainActor
final class EventKitCalendarService: CalendarService {

    // nonisolated(unsafe)：requestFullAccess* 是 nonisolated async，Swift 6 region
    // 检查不允许把 MainActor 隔离的实例发过去；EKEventStore 本身线程安全（Apple 文档）
    nonisolated(unsafe) private let eventStore = EKEventStore()

    /// Layer 1: 日历数据变化回调（AppDelegate 挂接，触发即时刷新）。
    /// 仅在权限已授予后才会触发（避免无权限时的死循环）。
    var onCalendarChanged: (() -> Void)?

    private var changeDebounceTask: Task<Void, Never>?
    /// 权限是否已授予（授予后才开启 EKEventStoreChanged 监听）
    private(set) var hasAccess = false
    private(set) var hasRemindersAccess = false
    /// 是否已尝试过请求权限（避免重复请求）
    private var hasRequestedAccess = false

    init() {}

    // MARK: - 权限请求（只调用一次，由 AppDelegate 在激活状态下调用）

    /// 请求日历 + 提醒事项权限。两者都授予时返回 true。
    /// 注意：accessory 应用需先临时切换为 .regular 激活策略才能弹窗。
    func requestAccess() async -> Bool {
        guard !hasRequestedAccess else {
            return hasAccess
        }
        hasRequestedAccess = true

        do {
            // 日历权限
            let eventsGranted = try await eventStore.requestFullAccessToEvents()
            // 提醒事项权限（独立于日历，需单独请求）
            let remindersGranted = try await eventStore.requestFullAccessToReminders()
            hasAccess = eventsGranted
            hasRemindersAccess = remindersGranted
            if eventsGranted || remindersGranted {
                startObservingChanges()
            }
            NSLog("[Calendar] access: events=\(eventsGranted), reminders=\(remindersGranted)")
            return eventsGranted
        } catch {
            NSLog("[Calendar] requestAccess error: \(error)")
            return false
        }
    }

    /// 当前权限状态（不触发请求）
    var currentAccessStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// 权限在之前的启动中已授予时调用：补挂 EKEventStoreChanged 监听。
    /// requestAccess() 只在首次（.notDetermined）走到，老用户不调这个的话
    /// 外部改日程只能等 15min 兜底轮询。
    func startObservingIfAuthorized() {
        let events = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let reminders = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        guard events || reminders else { return }
        hasAccess = events
        hasRemindersAccess = reminders
        startObservingChanges()
    }

    // MARK: - 事件监听（权限授予后才开启）

    private var isObserving = false

    private func startObservingChanges() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleDebouncedRefresh() }
        }
    }

    /// 1s 防抖：批量编辑场景下只触发一次刷新
    private func scheduleDebouncedRefresh() {
        guard hasAccess || hasRemindersAccess else { return } // 无权限时不触发，避免死循环
        changeDebounceTask?.cancel()
        changeDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.onCalendarChanged?()
        }
    }

    // MARK: - 拉取

    /// 可同步的事件日历：只保留用户手动创建或账户（iCloud/Google/Exchange 等）同步的可写日历。
    /// 排除系统自动生成的只读日历——「生日」「节假日」等订阅日历、Siri 建议（找到的活动）。
    nonisolated private static func isSyncableCalendar(_ calendar: EKCalendar) -> Bool {
        if calendar.type == .birthday || calendar.type == .subscription { return false }
        if let sourceType = calendar.source?.sourceType,
           sourceType == .birthdays || sourceType == .subscribed { return false }
        // 兜底：系统注入的日历（Siri 建议等）一律不可写，可写即用户/账户日历
        return calendar.allowsContentModifications
    }

    func fetchMeetings(in range: ClosedRange<Date>) async throws -> [Meeting] {
        var results: [Meeting] = []

        // 长生命周期 EKEventStore 的缓存可能落后于外部编辑，拉取前先刷新数据源
        eventStore.refreshSourcesIfNecessary()

        // ── 1. 日历事件 ──
        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        let syncableCalendars = eventStatus == .fullAccess
            ? eventStore.calendars(for: .event).filter(Self.isSyncableCalendar)
            : []
        if eventStatus == .fullAccess, !syncableCalendars.isEmpty {
            let predicate = eventStore.predicateForEvents(
                withStart: range.lowerBound, end: range.upperBound, calendars: syncableCalendars
            )
            let events = eventStore.events(matching: predicate)

            results += events.map { ev in
                let linkText = [ev.notes, ev.location, ev.url?.absoluteString]
                    .compactMap { $0 }.joined(separator: "\n")
                let linkInfo = Self.extractMeetingLink(from: linkText)
                return Meeting(
                    title: ev.title,
                    start: ev.startDate,
                    end: ev.endDate,
                    link: linkInfo?.0,
                    platform: linkInfo?.1,
                    attendees: ev.attendees?.compactMap(\.name) ?? [],
                    calendarName: ev.calendar.title
                )
            }
        }

        // ── 2. 提醒事项 ──
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        if reminderStatus == .fullAccess {
            let reminderCalendars = eventStore.calendars(for: .reminder)
            let predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: range.lowerBound, ending: range.upperBound,
                calendars: reminderCalendars
            )

            // fetchReminders(matching:completion:) 是 completion-based API，桥接为 async。
            // 注意：completion 在 EventKit 后台队列回调，闭包内不能执行 MainActor 隔离代码
            // （会触发运行时隔离断言崩溃）；EKReminder 非 Sendable 也不能跨隔离域传递。
            // 所以映射在回调队列上用 nonisolated 方法就地完成，只回传 Sendable 的 [Meeting]。
            let reminderMeetings: [Meeting] = await withCheckedContinuation { continuation in
                eventStore.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: Self.mapReminders(reminders ?? []))
                }
            }
            results += reminderMeetings
        }

        // 权限全无才报错
        if eventStatus != .fullAccess && reminderStatus != .fullAccess {
            throw CalendarServiceError.accessDenied
        }

        NSLog("[Calendar] calendars=%d, events=%d, range=\(range.lowerBound)~\(range.upperBound)", syncableCalendars.count, results.filter { !$0.isReminder }.count)
        return results.sorted { $0.start < $1.start }
    }

    /// EKReminder → Meeting 映射。nonisolated：在 EventKit 回调队列上执行，
    /// 不触碰 MainActor 状态（Meeting 为 Sendable struct，可安全跨队列返回）。
    nonisolated private static func mapReminders(_ reminders: [EKReminder]) -> [Meeting] {
        let cal = Calendar.current
        return reminders.compactMap { reminder -> Meeting? in
            guard let dc = reminder.dueDateComponents,
                  let dueDate = cal.date(from: dc) else { return nil }
            return Meeting(
                title: reminder.title ?? "(无标题)",
                start: dueDate,
                end: dueDate,
                link: reminder.url,
                platform: nil,
                attendees: [],
                calendarName: reminder.calendar.title,
                isReminder: true
            )
        }
    }

    // MARK: 会议链接提取（真实现 —— 纯字符串逻辑，6 大平台）

    /// 从日历事件备注/位置文本中提取第一个会议链接及其平台。
    /// 支持：Zoom / 腾讯会议 / Google Meet / Teams / 飞书 / 钉钉（integrations spec）。
    nonisolated static func extractMeetingLink(from notes: String?) -> (URL, MeetingPlatform)? {
        guard let notes, !notes.isEmpty else { return nil }
        // 链接字符集：到空白/引号/尖括号/右括号/方括号为止
        let tail = #"[^\s<>"'\)\]]+"#
        let patterns: [(pattern: String, platform: MeetingPlatform)] = [
            (#"https?://[\w.-]*zoom\.us/"# + tail, .zoom),
            (#"https?://meeting\.tencent\.com/"# + tail, .tencent),
            (#"https?://meet\.google\.com/"# + tail, .googleMeet),
            (#"https?://teams\.microsoft\.com/"# + tail, .teams),
            (#"https?://vc\.feishu\.cn/"# + tail, .feishu),
            (#"https?://[\w.-]*dingtalk\.com/"# + tail, .dingtalk),
        ]
        // 取文本中最早出现的匹配（而非按平台顺序），避免备注含多平台链接时取错
        var best: (range: Range<String.Index>, platform: MeetingPlatform)?
        for (pattern, platform) in patterns {
            if let range = notes.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                if best == nil || range.lowerBound < best!.range.lowerBound {
                    best = (range, platform)
                }
            }
        }
        guard let best, let url = URL(string: String(notes[best.range])) else { return nil }
        return (url, best.platform)
    }
}
