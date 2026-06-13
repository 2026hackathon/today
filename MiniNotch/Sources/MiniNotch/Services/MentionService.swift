import Foundation

// ============================================================
// MentionService —— 收集各渠道「@我」的条目（只读跳转）。
// Owner: C
//
// 数据源（复用 Jira 同一套 Atlassian 凭据，Confluence 同站点 /wiki）：
// - Jira:       JQL  comment ~ currentUser()         评论里@我的 issue
// - Confluence: CQL  mention = currentUser()          页面里@我的内容
// 两者都用 Basic 认证（email:apiToken），实测可用（2026-06 wonder 站点）。
//
// Mock 兜底：未配置 Jira 凭据时返回演示数据。AppDelegate 按配置装配。
// ============================================================

@MainActor
protocol MentionService: AnyObject {
    func fetchMentions() async throws -> [Mention]
}

// MARK: - Mock（2 条演示，未配置时兜底）

@MainActor
final class MockMentionService: MentionService {
    init() {}
    func fetchMentions() async throws -> [Mention] {
        try? await Task.sleep(for: .seconds(0.2))
        return [
            Mention(id: "MD-1024", source: .jira, title: "MD-1024 修复登录 bug",
                    context: "In Progress", url: URL(string: "https://example.atlassian.net/browse/MD-1024"), updated: Date()),
            Mention(id: "conf-1", source: .confluence, title: "Q3 技术方案评审",
                    context: "ENG 空间", url: URL(string: "https://example.atlassian.net/wiki"), updated: Date()),
        ]
    }
}

// MARK: - 真实现（Atlassian Cloud：Jira JQL + Confluence CQL）

@MainActor
final class RealMentionService: MentionService {

    private let baseURL: String   // 站点根，如 https://xx.atlassian.net
    private let email: String
    private let apiToken: String

    /// 提及时间窗（天）：只看近一周@我，像通知 feed 而非陈年积压
    static let recentDays = 7

    init(baseURL: String, email: String, apiToken: String) {
        var b = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        // 容忍用户把 /wiki 也填进来：取站点根
        if b.hasSuffix("/wiki") { b = String(b.dropLast(5)) }
        self.baseURL = b
        self.email = email
        self.apiToken = apiToken
    }

    func fetchMentions() async throws -> [Mention] {
        guard !baseURL.isEmpty, !email.isEmpty, !apiToken.isEmpty else {
            throw MentionServiceError.notConfigured
        }
        // 两个源各自失败不拖垮整体（某个权限不足/接口变动时另一个仍可用）
        async let jira = (try? fetchJiraMentions()) ?? []
        async let confluence = (try? fetchConfluenceMentions()) ?? []
        let all = await jira + confluence
        return all.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
    }

    // MARK: Jira —— comment ~ currentUser()

    private func fetchJiraMentions() async throws -> [Mention] {
        // 第一步：近 N 天评论里出现过我的候选 issue（粗筛，含我自己评论的/被@的）
        var comps = URLComponents(string: "\(baseURL)/rest/api/3/search/jql")
        let jql = "comment ~ currentUser() AND updated >= -\(Self.recentDays)d ORDER BY updated DESC"
        comps?.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: "summary,status,lastViewed"),
            URLQueryItem(name: "maxResults", value: "15"),
        ]
        guard let url = comps?.url else { return [] }
        let res = try JSONDecoder().decode(JiraSearch.self, from: try await get(url))
        let me = try await myAccountId()

        // 第二步：逐 issue 精筛——「最近一条@我的评论」之后，我是否已（回复 / 任何端打开过 issue）。
        // 都没有才算未读。跨端真实：在网页/手机回复或打开过 → 下次轮询自动消失
        var result: [Mention] = []
        for issue in res.issues {
            let viewedAt = issue.fields.lastViewed.flatMap(Self.parseJiraDate)
            guard let mentionAt = try await latestUnansweredMention(
                issueKey: issue.key, me: me, viewedAt: viewedAt) else { continue }
            result.append(Mention(
                id: issue.key,
                source: .jira,
                title: "\(issue.key) \(issue.fields.summary)",
                context: issue.fields.status?.name,
                url: URL(string: "\(baseURL)/browse/\(issue.key)"),
                updated: mentionAt   // 用「@我的时间」作为时间戳，本地已读/重现据此判断
            ))
        }
        return result
    }

    /// 返回「最近一条@我、且我之后未处理」的评论时间；已处理(回复/打开过 issue)或无@我则 nil。
    /// viewedAt = 该 issue 的 lastViewed（跨端「我打开过」）
    private func latestUnansweredMention(issueKey: String, me: String, viewedAt: Date?) async throws -> Date? {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(issueKey)/comment?maxResults=50") else { return nil }
        let raw = try await get(url)
        guard let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let comments = obj["comments"] as? [[String: Any]] else { return nil }

        var latestMentionOfMe: Date?
        var myLatestComment: Date?
        for c in comments {
            let created = (c["created"] as? String).flatMap(Self.parseJiraDate)
            let authorId = (c["author"] as? [String: Any])?["accountId"] as? String
            if authorId == me, let created {
                myLatestComment = max(myLatestComment ?? .distantPast, created)
            }
            var ids = Set<String>()
            Self.scanMentionIDs(c["body"], into: &ids)
            if ids.contains(me), let created {
                latestMentionOfMe = max(latestMentionOfMe ?? .distantPast, created)
            }
        }
        guard let mentionAt = latestMentionOfMe else { return nil }
        // 已处理 = 被@之后我回过评论，或我在任何端打开过该 issue（lastViewed 晚于被@）
        if let reply = myLatestComment, reply >= mentionAt { return nil }
        if let viewedAt, viewedAt >= mentionAt { return nil }
        return mentionAt
    }

    /// 递归扫描 ADF 评论体里的 mention 节点 accountId
    nonisolated private static func scanMentionIDs(_ node: Any?, into set: inout Set<String>) {
        if let dict = node as? [String: Any] {
            if dict["type"] as? String == "mention",
               let id = (dict["attrs"] as? [String: Any])?["id"] as? String {
                set.insert(id)
            }
            for v in dict.values { scanMentionIDs(v, into: &set) }
        } else if let arr = node as? [Any] {
            for v in arr { scanMentionIDs(v, into: &set) }
        }
    }

    /// 当前用户 accountId（缓存，首次拉 /myself）
    private var cachedAccountId: String?
    private func myAccountId() async throws -> String {
        if let id = cachedAccountId { return id }
        guard let url = URL(string: "\(baseURL)/rest/api/3/myself") else { throw MentionServiceError.notConfigured }
        let me = try JSONDecoder().decode(Myself.self, from: try await get(url))
        cachedAccountId = me.accountId
        return me.accountId
    }
    private struct Myself: Decodable { let accountId: String }

    // MARK: Confluence —— mention = currentUser()

    private func fetchConfluenceMentions() async throws -> [Mention] {
        var comps = URLComponents(string: "\(baseURL)/wiki/rest/api/content/search")
        // 同样加时间窗（Confluence 无 per-user lastViewed，本地追踪兜已读）
        let cql = "mention = currentUser() and lastmodified >= now(\"-\(Self.recentDays)d\") order by lastmodified desc"
        comps?.queryItems = [
            URLQueryItem(name: "cql", value: cql),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "expand", value: "space,version"),
        ]
        guard let url = comps?.url else { return [] }
        let data = try await get(url)
        let res = try JSONDecoder().decode(ConfluenceSearch.self, from: data)
        return res.results.map { page in
            let webui = page._links?.webui
            return Mention(
                id: "conf-\(page.id)",
                source: .confluence,
                title: page.title,
                context: page.space?.name,
                url: webui.flatMap { URL(string: "\(baseURL)/wiki\($0)") },
                updated: page.version?.when.flatMap(Self.parseISO)
            )
        }
    }

    // MARK: HTTP

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let cred = Data("\(email):\(apiToken)".utf8).base64EncodedString()
        req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            NSLog("[Mention] HTTP \(code): \(url.path)")
            throw MentionServiceError.http(code)
        }
        return data
    }

    // MARK: 响应模型（只取要用的字段）

    private struct JiraSearch: Decodable { let issues: [Issue] }
    private struct Issue: Decodable { let key: String; let fields: Fields }
    private struct Fields: Decodable {
        let summary: String
        let status: Named?
        let updated: String?
        let lastViewed: String?
    }
    private struct Named: Decodable { let name: String }

    private struct ConfluenceSearch: Decodable { let results: [Page] }
    private struct Page: Decodable {
        let id: String
        let title: String
        let space: Space?
        let version: Version?
        let _links: Links?
        struct Space: Decodable { let name: String? }
        struct Version: Decodable { let when: String? }
        struct Links: Decodable { let webui: String? }
    }

    // MARK: 日期

    nonisolated private static func parseISO(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s)
    }
    /// Jira updated 形如 2026-06-13T10:00:00.000+0800
    nonisolated private static func parseJiraDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return f.date(from: s)
    }
}

enum MentionServiceError: Error {
    case notConfigured
    case http(Int)
}
