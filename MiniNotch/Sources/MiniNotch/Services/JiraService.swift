import Foundation

// ============================================================
// JiraService —— 指派 ticket 拉取协议 + Mock + 真实现骨架。
// Owner: C
//
// 接真实现步骤（C）：
// 1. RealJiraService 用 settings.jiraBaseURL / jiraEmail / jiraAPIToken
//    请求 /rest/api/3/search?jql=assignee=currentUser() AND statusCategory!=Done。
// 2. 响应 issues[] → 映射 Todo（source .jira，jiraKey/jiraURL/jiraStatus）。
// 3. AppDelegate 装配处换 RealJiraService，60s 轮询调 store.mergeJiraTodos(_:)。
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
    func fetchAssignedTickets() async throws -> [Todo]
}

// MARK: - Mock 实现（3 条演示 ticket，integrations spec）

@MainActor
final class MockJiraService: JiraService {

    /// Demo「现场分配」开关：置 true 后，下一次 fetch 起额外返回 MD-1077。
    /// AppStore.mergeJiraTodos 按 jiraKey 去重，重复返回不会产生重复 todo。
    var extraTicketArmed = false
    private var extraTicketReleased = false

    init() {}

    func fetchAssignedTickets() async throws -> [Todo] {
        try? await Task.sleep(for: .seconds(0.3)) // 模拟网络
        if extraTicketArmed {
            extraTicketArmed = false
            extraTicketReleased = true
        }
        var tickets = [
            Self.ticket(key: "MD-1024", title: "修复登录 bug", status: "In Progress", priority: .high),
            Self.ticket(key: "MD-1031", title: "优化首页加载", status: "To Do", priority: .medium),
            Self.ticket(key: "MD-1042", title: "用户反馈调研", status: "To Do", priority: .low),
        ]
        if extraTicketReleased {
            tickets.append(Self.ticket(key: "MD-1077", title: "支付回调超时排查", status: "To Do", priority: .high))
        }
        return tickets
    }

    private static func ticket(key: String, title: String, status: String, priority: Priority) -> Todo {
        Todo(
            title: title,
            source: .jira,
            priority: priority,
            jiraKey: key,
            jiraURL: URL(string: "https://example.atlassian.net/browse/\(key)"),
            jiraStatus: status
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

    func fetchAssignedTickets() async throws -> [Todo] {
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
            Todo(
                title: issue.fields.summary,
                source: .jira,
                priority: Self.mapPriority(issue.fields.priority?.name),
                dueDate: issue.fields.duedate.flatMap(Self.parseDueDate),
                jiraKey: issue.key,
                jiraURL: URL(string: "\(baseURL)/browse/\(issue.key)"),
                jiraStatus: issue.fields.status.name
            )
        }
    }

    private func fetchPage(nextPageToken: String?) async throws -> SearchResponse {
        var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql")
        var items = [
            URLQueryItem(name: "jql", value: "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"),
            URLQueryItem(name: "fields", value: "summary,status,priority,duedate"),
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

    // MARK: 响应模型（只取要用的字段）

    private struct SearchResponse: Decodable {
        let issues: [Issue]
        let isLast: Bool?
        let nextPageToken: String?
    }
    private struct Issue: Decodable {
        let key: String
        let fields: Fields
    }
    private struct Fields: Decodable {
        let summary: String
        let status: NamedField
        let priority: NamedField?
        let duedate: String?
    }
    private struct NamedField: Decodable {
        let name: String
    }
}
