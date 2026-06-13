import Foundation

// ============================================================
// GraphEmailService —— 通过 Microsoft Graph 拉邮件（email-o365-oauth）。
// O365 的 IMAP 被管理员锁死时改走 Graph：用 Mail.Read（OAuth2，MicrosoftOAuth），
// 不依赖邮箱 IMAP 协议开关。来源识别/链接归一/隐私预处理复用 IMAP 那套。
// 跳转链接用 webLink（OWA），slack/jira 优先用正文里的深链。
// ============================================================

@MainActor
final class GraphEmailService: EmailService {

    private let maxFetch = 20

    func fetchNewMessages() async throws -> [EmailDigestInput] {
        let token = try await MicrosoftOAuth.shared.validAccessToken()

        var comps = URLComponents(string: "https://graph.microsoft.com/v1.0/me/messages")!
        comps.queryItems = [
            URLQueryItem(name: "$filter", value: "isRead eq false"),
            URLQueryItem(name: "$top", value: "\(maxFetch)"),
            URLQueryItem(name: "$select", value: "id,subject,from,bodyPreview,receivedDateTime,webLink,internetMessageId"),
            URLQueryItem(name: "$orderby", value: "receivedDateTime desc"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            let raw = String(data: data.prefix(300), encoding: .utf8) ?? ""
            NSLog("[Graph] GET /me/messages HTTP \(code): \(raw)")
            throw EmailServiceError.server("Graph HTTP \(code)")
        }

        let decoded = try JSONDecoder().decode(GraphMessagesResponse.self, from: data)
        let iso = ISO8601DateFormatter()

        return decoded.value.compactMap { msg -> EmailDigestInput? in
            let address = msg.from?.emailAddress?.address ?? ""
            let domain = address.split(separator: "@").last.map(String.init) ?? ""
            let subject = msg.subject ?? ""
            // 送 AI 之前的一段代码过滤：丢弃明显噪音/无效邮件 + 非真人自动通知（收件箱只留真人需处理）
            guard !EmailPreprocess.isNoise(domain: domain, subject: subject),
                  !EmailPreprocess.isAutomatedNotification(from: address, subject: subject)
            else { return nil }

            let body = msg.bodyPreview ?? ""
            let source = EmailClassifier.source(fromDomain: domain, listId: nil, body: body)
            let webURL = msg.webLink.flatMap { URL(string: $0) }
            // 链接归一契约：email 来源的原邮箱链接 = Graph 的 webLink（OWA 原邮件 web 链接，
            // 点开即邮箱里那封原始邮件）。slack/jira 仍优先正文深链。
            let link = EmailClassifier.deepLink(source: source, body: body) ?? webURL

            return EmailDigestInput(
                messageId: msg.internetMessageId ?? msg.id,
                source: source,
                link: link,
                sender: msg.from?.emailAddress?.name ?? (address.isEmpty ? "未知" : address),
                subject: subject,
                bodyExcerpt: EmailPreprocess.excerpt(body),
                receivedAt: msg.receivedDateTime.flatMap { iso.date(from: $0) } ?? Date()
            )
        }
    }
}

// MARK: - Graph JSON

private struct GraphMessagesResponse: Decodable { let value: [GraphMessage] }

private struct GraphMessage: Decodable {
    let id: String
    let subject: String?
    let from: GraphRecipient?
    let bodyPreview: String?
    let receivedDateTime: String?
    let webLink: String?
    let internetMessageId: String?
}

private struct GraphRecipient: Decodable { let emailAddress: GraphAddress? }
private struct GraphAddress: Decodable { let name: String?; let address: String? }
