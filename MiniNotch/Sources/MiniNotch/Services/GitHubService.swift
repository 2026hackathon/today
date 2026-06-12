import Foundation

// ============================================================
// GitHubService —— GitHub PR 拉取（结构完全对标 JiraService）。
// Owner: C
//
// PR 与 Jira ticket 同构：外部只读、轮询镜像、新分配通知。
// 复用 Todo 的 ticket 字段：jiraKey="repo#123"、jiraURL=PR 页面、
// jiraStatus="待 Review"/"已指派"/"Draft"、jiraAssigner=PR 作者。
// ============================================================

enum GitHubServiceError: Error {
    case notConfigured
    case http(Int)
}

@MainActor
protocol GitHubService: AnyObject {
    /// 拉取需要我处理的 open PR（待我 review + 指派给我），按 URL 去重
    func fetchMyPullRequests() async throws -> [Todo]
}

// MARK: - Mock（Demo 兜底 + 「模拟 PR 新分配」）

@MainActor
final class MockGitHubService: GitHubService {

    /// Demo「现场请求 review」开关，与 MockJiraService.extraTicketArmed 同款
    var extraPRArmed = false
    private var extraPRReleased = false

    init() {}

    func fetchMyPullRequests() async throws -> [Todo] {
        try? await Task.sleep(for: .seconds(0.3))
        if extraPRArmed {
            extraPRArmed = false
            extraPRReleased = true
        }
        var prs = [
            Self.pr(repo: "today", number: 42, title: "feat: 灵动岛动效系统", author: "linjia", status: "待 Review"),
            Self.pr(repo: "today", number: 38, title: "fix: 日历同步时区问题", author: "zhouyan", status: "Draft", draft: true),
        ]
        if extraPRReleased {
            prs.append(Self.pr(repo: "today", number: 47, title: "feat: AI 晨报真实生成", author: "chenhao", status: "待 Review"))
        }
        return prs
    }

    private static func pr(repo: String, number: Int, title: String, author: String, status: String, draft: Bool = false) -> Todo {
        Todo(
            title: title,
            source: .github,
            priority: draft ? .low : .medium,
            jiraKey: "\(repo)#\(number)",
            jiraURL: URL(string: "https://github.com/2026hackathon/\(repo)/pull/\(number)"),
            jiraStatus: status,
            jiraAssigner: author
        )
    }
}

// MARK: - 真实现（GitHub Search API）

@MainActor
final class RealGitHubService: GitHubService {

    private let token: String

    /// - Parameter token: settings.githubToken（PAT 或 gh CLI 的 OAuth token 均可）
    init(token: String) {
        self.token = token
    }

    func fetchMyPullRequests() async throws -> [Todo] {
        guard !token.isEmpty else { throw GitHubServiceError.notConfigured }

        // Search API 不支持 OR，两个查询合并去重：
        // 待我 review 的优先（同一 PR 两边都命中时保留「待 Review」状态）
        let reviewRequested = try await search(query: "is:pr is:open review-requested:@me", status: "待 Review")
        let assigned = try await search(query: "is:pr is:open assignee:@me", status: "已指派")

        var seen = Set<String>()
        var result: [Todo] = []
        for pr in reviewRequested + assigned {
            guard let key = pr.jiraKey, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(pr)
        }
        return result
    }

    private func search(query: String, status: String) async throws -> [Todo] {
        var components = URLComponents(string: "https://api.github.com/search/issues")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "sort", value: "updated"),
        ]
        guard let url = components?.url else { throw GitHubServiceError.notConfigured }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            NSLog("[GitHub] search failed: HTTP \(code)")
            throw GitHubServiceError.http(code)
        }

        let result = try JSONDecoder().decode(SearchResponse.self, from: data)
        return result.items.map { item in
            // repository_url = https://api.github.com/repos/owner/repo → 取 repo 名
            let repo = item.repositoryURL.split(separator: "/").last.map(String.init) ?? "?"
            let isDraft = item.draft ?? false
            return Todo(
                title: item.title,
                source: .github,
                priority: isDraft ? .low : .medium,
                jiraKey: "\(repo)#\(item.number)",
                jiraURL: URL(string: item.htmlURL),
                jiraStatus: isDraft ? "Draft" : status,
                jiraAssigner: item.user?.login
            )
        }
    }

    // MARK: 响应模型

    private struct SearchResponse: Decodable {
        let items: [Item]
    }
    private struct Item: Decodable {
        let number: Int
        let title: String
        let htmlURL: String
        let repositoryURL: String
        let draft: Bool?
        let user: User?

        enum CodingKeys: String, CodingKey {
            case number, title, draft, user
            case htmlURL = "html_url"
            case repositoryURL = "repository_url"
        }
    }
    private struct User: Decodable {
        let login: String
    }
}
