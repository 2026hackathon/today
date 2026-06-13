import Foundation

// ============================================================
// JiraService —— 指派 ticket 拉取协议 + Mock + 真实现骨架。
// Owner: C
//
// 接真实现步骤（C）：
// 1. RealJiraService 用 settings.jiraBaseURL / jiraEmail / jiraAPIToken
//    请求 /rest/api/3/search?jql=assignee=currentUser() AND statusCategory!=Done。
// 2. 响应 issues[] → 映射 WorkItem（source .jira，key/url/status/statusCategory）。
// 3. AppDelegate 装配处换 RealJiraService，60s 轮询调 store.mergeJiraWorkItems(_:)。
//    保留 MockJiraService（Demo 兜底 + 「现场分配」演示）。
// ============================================================

enum JiraServiceError: Error {
    /// baseURL/email/token 未配置或真实现未接
    case notConfigured
    case invalidResponse
    /// 非 2xx 响应（设置页「测试连接」按状态码给出具体提示）
    case http(Int)
}

@MainActor
protocol JiraService: AnyObject {
    /// 拉取指派给当前用户且未完成的 tickets（真实现轮询周期 60s，integrations spec）
    func fetchAssignedTickets() async throws -> [WorkItem]
}

// MARK: - Mock 实现（3 条演示 ticket，integrations spec）

@MainActor
final class MockJiraService: JiraService {

    /// Demo「现场分配」开关：置 true 后，下一次 fetch 起额外返回 MD-1077。
    /// AppStore.mergeWorkItems 按 key 去重，重复返回不会产生重复工作项。
    var extraTicketArmed = false
    private var extraTicketReleased = false

    init() {}

    func fetchAssignedTickets() async throws -> [WorkItem] {
        try? await Task.sleep(for: .seconds(0.3)) // 模拟网络
        if extraTicketArmed {
            extraTicketArmed = false
            extraTicketReleased = true
        }
        var tickets = [
            Self.ticket(key: "MD-1024", title: "修复登录 bug", status: "In Progress", priority: .high, assigner: "陈昊", points: 3),
            Self.ticket(key: "MD-1031", title: "优化首页加载", status: "To Do", priority: .medium, assigner: "林嘉", points: 5),
            Self.ticket(key: "MD-1042", title: "用户反馈调研", status: "To Do", priority: .low, assigner: "陈昊", points: 2),
        ]
        if extraTicketReleased {
            tickets.append(Self.ticket(key: "MD-1077", title: "支付回调超时排查", status: "To Do", priority: .high, assigner: "周彦", points: 3))
        }
        return tickets
    }

    private static func ticket(
        key: String, title: String, status: String, priority: Priority,
        assigner: String? = nil, points: Double? = nil
    ) -> WorkItem {
        WorkItem(
            key: key,
            title: title,
            source: .jira,
            status: status,
            statusCategory: status == "In Progress" ? "indeterminate" : "new",
            assigner: assigner,
            storyPoints: points,
            url: URL(string: "https://example.atlassian.net/browse/\(key)"),
            priority: priority
        )
    }
}

// MARK: - 真实现（Jira Cloud REST v3）

/// 注意端点：Jira Cloud 已下线旧 `GET /rest/api/3/search`，
/// 现行端点是 `GET /rest/api/3/search/jql`（2026-06 在 wonder.atlassian.net 实测通过）。
@MainActor
final class RealJiraService: JiraService {

    private let baseURL: String
    private let email: String
    private let apiToken: String

    /// - Parameters: 来自 settings.jiraBaseURL / jiraEmail / jiraAPIToken
    init(baseURL: String, email: String, apiToken: String) {
        // 容忍用户在设置里多敲一个尾部斜杠
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.email = email
        self.apiToken = apiToken
    }

    func fetchAssignedTickets() async throws -> [WorkItem] {
        guard !baseURL.isEmpty, !email.isEmpty, !apiToken.isEmpty else {
            throw JiraServiceError.notConfigured
        }

        // 分页拉全（jira-sync-prune spec）：清理逻辑要求结果完整，截断会误删。
        // 5 页 × 50 条封顶，超出属异常工作量，不再翻页。
        var issues: [Issue] = []
        var pageToken: String?
        for _ in 0..<5 {
            let page = try await fetchPage(nextPageToken: pageToken)
            issues += page.issues
            guard page.isLast == false, let token = page.nextPageToken else { break }
            pageToken = token
        }

        return issues.map { issue in
            WorkItem(
                key: issue.key,
                title: issue.fields.summary,
                source: .jira,
                status: issue.fields.status.name,
                statusCategory: issue.fields.status.statusCategory?.key,
                assigner: Self.extractAssigner(from: issue.changelog),
                storyPoints: issue.fields.storyPoints,
                url: URL(string: "\(baseURL)/browse/\(issue.key)"),
                priority: Self.mapPriority(issue.fields.priority?.name)
            )
        }
    }

    /// Story Points 字段 ID —— wonder.atlassian.net 实测为 customfield_10025
    /// （Jira 每个站点不同，换站点用 GET /rest/api/3/field 搜 "Story Points"，
    /// 同时改这里和 Fields.CodingKeys）
    private static let storyPointsFieldID = "customfield_10025"

    private func fetchPage(nextPageToken: String?) async throws -> SearchResponse {
        var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql")
        var items = [
            URLQueryItem(name: "jql", value: "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"),
            URLQueryItem(name: "fields", value: "summary,status,priority,duedate,\(Self.storyPointsFieldID)"),
            // changelog 用于提取「谁指派给我的」（最近一次 assignee 变更的操作人）
            URLQueryItem(name: "expand", value: "changelog"),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        if let nextPageToken {
            items.append(URLQueryItem(name: "nextPageToken", value: nextPageToken))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw JiraServiceError.notConfigured }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let credentials = Data("\(email):\(apiToken)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            NSLog("[Jira] fetch failed: HTTP \(code)")
            throw JiraServiceError.http(code)
        }
        return try JSONDecoder().decode(SearchResponse.self, from: data)
    }

    /// Jira 优先级名 → 三档（integrations spec delta）
    nonisolated private static func mapPriority(_ name: String?) -> Priority {
        switch name?.lowercased() {
        case "highest", "high", "blocker", "critical": .high
        case "medium": .medium
        default: .low
        }
    }

    /// duedate 是 "yyyy-MM-dd"（无时间）→ 按当天 18:00 进入提醒系统
    nonisolated private static func parseDueDate(_ raw: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        guard let day = f.date(from: raw) else { return nil }
        return Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: day)
    }

    /// 「谁指派给我的」= changelog 里最近一次 assignee 变更的操作人。
    /// histories 顺序不保证，按 created（ISO 字符串可比较）取最新。
    nonisolated private static func extractAssigner(from changelog: Changelog?) -> String? {
        changelog?.histories
            .filter { history in history.items.contains { $0.field == "assignee" } }
            .max { $0.created < $1.created }?
            .author?.displayName
    }

    // MARK: 响应模型（只取要用的字段）

    private struct SearchResponse: Decodable {
        let issues: [Issue]
        let isLast: Bool?
        let nextPageToken: String?
    }
    private struct Issue: Decodable {
        let key: String
        let fields: Fields
        let changelog: Changelog?
    }
    private struct Fields: Decodable {
        let summary: String
        let status: StatusField
        let priority: NamedField?
        let duedate: String?
        let storyPoints: Double?

        enum CodingKeys: String, CodingKey {
            case summary, status, priority, duedate
            case storyPoints = "customfield_10025" // 与 storyPointsFieldID 保持一致
        }
    }
    private struct NamedField: Decodable {
        let name: String
    }
    private struct StatusField: Decodable {
        let name: String
        let statusCategory: StatusCategory?
    }
    private struct StatusCategory: Decodable {
        let key: String
    }
    private struct Changelog: Decodable {
        let histories: [ChangeHistory]
    }
    private struct ChangeHistory: Decodable {
        let created: String
        let author: ChangeAuthor?
        let items: [ChangeItem]
    }
    private struct ChangeAuthor: Decodable {
        let displayName: String?
    }
    private struct ChangeItem: Decodable {
        let field: String?
    }
}
