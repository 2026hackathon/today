import Foundation

// ============================================================
// EmailService —— 邮件拉取协议 + Mock + 来源识别/链接归一/隐私预处理。
// Owner: B
//
// 接真实现步骤（group 7）：
// 1. RealEmailService 用 settings.emailImapHost / emailAddress / emailAppPassword
//    经 IMAP 拉取近 N 封未读邮件。
// 2. 每封原始邮件 → EmailClassifier 判定来源 + 归一链接、EmailPreprocess 截断正文，
//    产出 EmailDigestInput。
// 3. AppDelegate 装配处按凭据齐全切 Real，否则 Mock；轮询 60s。
//    AppDelegate 调 AIService.summarizeEmails 生成一句话 → 组装 Message。
//    注意：保留 MockEmailService 不要删（CODING_GUIDELINES：Demo 兜底）。
// ============================================================

enum EmailServiceError: Error {
    /// 凭据未配置或真实现未接
    case notConfigured
    case invalidResponse
    /// 鉴权/网络/非 2xx
    case transport
}

@MainActor
protocol EmailService: AnyObject {
    /// 拉取新邮件并完成来源识别 / 链接归一 / 隐私预处理，返回待 AI 摘要的输入。
    /// 失败抛错由装配层静默处理（保留上次数据，不弹错误 UI）。
    func fetchNewMessages() async throws -> [EmailDigestInput]
}

// MARK: - 来源识别与链接归一（email-integration spec）

enum EmailClassifier {

    /// 来源判定：Slack 通知 → slack；Jira 通知 → jira；其余 → email（不确定安全降级）
    static func source(fromDomain domain: String, listId: String?, body: String) -> MessageSource {
        let d = domain.lowercased()
        let list = (listId ?? "").lowercased()
        if d.hasSuffix("slack.com") || list.contains("slack") { return .slack }
        if d.hasSuffix("atlassian.net") || d.contains("jira") || body.contains("/browse/") { return .jira }
        return .email
    }

    /// 链接归一：slack → 深链；jira → issue 链接；其余/深链缺失 → 邮件链接（message://）
    static func normalizedLink(
        source: MessageSource, body: String, messageId: String
    ) -> URL? {
        switch source {
        case .slack:
            if let url = firstMatch(in: body, pattern: #"https?://[a-z0-9.-]*slack\.com/archives/[^\s"'<>]+"#) {
                return url
            }
        case .jira:
            if let url = firstMatch(in: body, pattern: #"https?://[a-z0-9.-]+/browse/[A-Z][A-Z0-9]+-\d+"#) {
                return url
            }
        case .email:
            break
        }
        return mailLink(messageId: messageId, body: body)
    }

    /// 邮件链接：优先 message:// 唤起本地邮件客户端，无 Message-ID 时回退正文里的 http 链接
    private static func mailLink(messageId: String, body: String) -> URL? {
        let trimmed = messageId.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        if !trimmed.isEmpty,
           let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "message://%3C\(encoded)%3E") {
            return url
        }
        return firstMatch(in: body, pattern: #"https?://[^\s"'<>]+"#)
    }

    private static func firstMatch(in text: String, pattern: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range, in: text) else { return nil }
        return URL(string: String(text[range]))
    }
}

// MARK: - 隐私预处理（email-integration spec：发送 AI 前截断 + 剥离签名/引用历史）

enum EmailPreprocess {
    /// 正文上限（约 1.5k 字），先剥离签名/引用历史再截断
    static func excerpt(_ body: String, limit: Int = 1500) -> String {
        var text = body
        // 剥离常见引用历史分隔（中英文回复线 / 引用块）
        for marker in ["\n>", "\n-----", "\n----- Original", "\n发件人:", "\n发件人：", "\nFrom:", "\nOn "] {
            if let r = text.range(of: marker) { text = String(text[..<r.lowerBound]) }
        }
        // 剥离签名（-- 或「此致」起）
        for marker in ["\n-- \n", "\n--\n", "\n此致", "\nBest regards", "\nThanks,"] {
            if let r = text.range(of: marker) { text = String(text[..<r.lowerBound]) }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > limit ? String(text.prefix(limit)) : text
    }

    /// 明显噪音预过滤（营销 / 纯系统通知）：true 表示跳过、不入库不送 LLM
    static func isNoise(domain: String, subject: String) -> Bool {
        let d = domain.lowercased(), s = subject.lowercased()
        let noiseDomains = ["newsletter", "noreply-marketing", "mailchimp", "sendgrid.net"]
        let noiseWords = ["unsubscribe", "退订", "促销", "newsletter", "广告"]
        return noiseDomains.contains(where: d.contains) || noiseWords.contains(where: s.contains)
    }
}

// MARK: - 一句话摘要的规则化兜底（无 AI Key / AI 失败时使用，不出网）

enum EmailSummary {
    static func rule(_ input: EmailDigestInput) -> String {
        let who = input.sender.map { "\($0)：" } ?? ""
        let subject = input.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(who)\(subject.isEmpty ? "新邮件" : subject)"
    }
}

// MARK: - Mock 实现（3 条演示：slack / jira / 普通邮件，integrations spec）

@MainActor
final class MockEmailService: EmailService {

    /// Demo「现场来信」开关：置 true 后下一次 fetch 额外返回 1 封新邮件
    var extraMailArmed = false
    private var extraMailReleased = false

    init() {}

    func fetchNewMessages() async throws -> [EmailDigestInput] {
        try? await Task.sleep(for: .seconds(0.3)) // 模拟网络
        if extraMailArmed { extraMailArmed = false; extraMailReleased = true }
        var raws = Self.fixtures
        if extraMailReleased {
            raws.append(("urgent-\(raws.count)", "boss@xm.wonder.com", "李总", "今天下班前给我 Q3 复盘结论", nil,
                         "麻烦今天 18:00 前把 Q3 复盘的结论发我，明早要用。"))
        }
        // 经真实分类/归一/预处理产出（Mock 也走同一套逻辑，保证 demo 即验证）
        return raws.compactMap { id, from, sender, subject, listId, body in
            let domain = from.split(separator: "@").last.map(String.init) ?? ""
            guard !EmailPreprocess.isNoise(domain: domain, subject: subject) else { return nil }
            let source = EmailClassifier.source(fromDomain: domain, listId: listId, body: body)
            return EmailDigestInput(
                messageId: id,
                source: source,
                link: EmailClassifier.normalizedLink(source: source, body: body, messageId: id),
                sender: sender,
                subject: subject,
                bodyExcerpt: EmailPreprocess.excerpt(body),
                receivedAt: Date()
            )
        }
    }

    /// (messageId, from, sender, subject, listId, body)
    private static let fixtures: [(String, String, String, String, String?, String)] = [
        ("slack-demo-1", "notifications@wonder.slack.com", "#dev-frontend", "张伟 在 #dev-frontend 提到了你",
         "<dev-frontend.wonder.slack.com>",
         "张伟：登录页的埋点能今天加上吗？详见 https://wonder.slack.com/archives/C012AB3CD/p1718260000"),
        ("jira-demo-1", "jira@wonder.atlassian.net", "周彦", "(MD-1099) 请评审支付模块设计",
         nil,
         "周彦请你评审 MD-1099。链接：https://wonder.atlassian.net/browse/MD-1099"),
        ("email-demo-1", "lily@client-corp.com", "Lily Chen", "关于下周合作的几个问题",
         nil,
         "你好，下周的合作有三个问题想确认，方便周三前回复吗？\n\n此致\nLily"),
    ]
}
