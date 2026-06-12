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

// MARK: - 真实现骨架（C 接管）

@MainActor
final class RealJiraService: JiraService {

    private let baseURL: String
    private let email: String
    private let apiToken: String

    /// - Parameters: 来自 settings.jiraBaseURL / jiraEmail / jiraAPIToken
    init(baseURL: String, email: String, apiToken: String) {
        self.baseURL = baseURL
        self.email = email
        self.apiToken = apiToken
    }

    func fetchAssignedTickets() async throws -> [Todo] {
        guard !baseURL.isEmpty, !email.isEmpty, !apiToken.isEmpty else {
            throw JiraServiceError.notConfigured
        }
        // TODO: C 实现真实 Jira 调用：
        // 1. GET {baseURL}/rest/api/3/search?jql=assignee=currentUser()%20AND%20statusCategory!=Done
        //    &fields=summary,status,priority,duedate
        // 2. Header: Authorization: Basic base64("\(email):\(apiToken)")，Accept: application/json
        // 3. let (data, _) = try await URLSession.shared.data(for: request)
        // 4. 解析 issues[] → Todo(source: .jira, jiraKey: key,
        //    jiraURL: URL("\(baseURL)/browse/\(key)"), jiraStatus: fields.status.name)
        // 5. 网络失败时调用方静默用上次缓存（design.md 第 5 节降级策略）
        throw JiraServiceError.notConfigured
    }
}
