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
    /// 今日所有会议（按时间排序由调用方/AppStore 派生属性处理）
    func fetchTodayMeetings() async throws -> [Meeting]
}

// MARK: - Mock 实现（今日 2 场会议，与 prototype 一致 —— integrations spec）

@MainActor
final class MockCalendarService: CalendarService {

    init() {}

    func fetchTodayMeetings() async throws -> [Meeting] {
        try? await Task.sleep(for: .seconds(0.2)) // 模拟读取
        return AppStore.demoMeetings()
    }
}

// MARK: - EventKit 真实现骨架（C 接管）

@MainActor
final class EventKitCalendarService: CalendarService {

    private let eventStore = EKEventStore()

    init() {}

    func fetchTodayMeetings() async throws -> [Meeting] {
        // TODO: C 实现 EventKit 拉取：
        // 1. let granted = try await eventStore.requestFullAccessToEvents()  // macOS 14+
        //    guard granted else { throw CalendarServiceError.accessDenied }
        // 2. let cal = Calendar.current
        //    let start = cal.startOfDay(for: Date())
        //    let end = cal.date(byAdding: .day, value: 1, to: start)!
        //    let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        // 3. let events = eventStore.events(matching: predicate)
        // 4. events.map { ev in
        //        let link = Self.extractMeetingLink(from: [ev.notes, ev.location, ev.url?.absoluteString]
        //            .compactMap { $0 }.joined(separator: "\n"))
        //        return Meeting(title: ev.title, start: ev.startDate, end: ev.endDate,
        //                       link: link?.0, platform: link?.1,
        //                       attendees: ev.attendees?.compactMap(\.name) ?? [],
        //                       calendarName: ev.calendar.title)
        //    }
        throw CalendarServiceError.notImplemented
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
