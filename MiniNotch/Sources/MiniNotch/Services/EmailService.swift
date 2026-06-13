import Foundation
import Network

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
    /// 服务器返回 NO/BAD（含原文，便于定位认证被拒 / IMAP 未开）
    case server(String)
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

    /// 来源深链（slack archives / jira browse），无则 nil
    static func deepLink(source: MessageSource, body: String) -> URL? {
        switch source {
        case .slack:
            return firstMatch(in: body, pattern: #"https?://[a-z0-9.-]*slack\.com/archives/[^\s"'<>]+"#)
        case .jira:
            return firstMatch(in: body, pattern: #"https?://[a-z0-9.-]+/browse/[A-Z][A-Z0-9]+-\d+"#)
        case .email:
            return nil
        }
    }

    /// 链接归一（IMAP 用）：slack/jira 深链 → email 来源的「原邮箱链接」兜底
    static func normalizedLink(
        source: MessageSource, body: String, messageId: String, host: String
    ) -> URL? {
        deepLink(source: source, body: body) ?? mailLink(messageId: messageId, host: host)
    }

    /// email 来源的原邮箱链接：直接指向邮箱网页端那封原始邮件，点开即原邮件。
    /// Gmail → 网页端 rfc822msgid 链接；其余通用 IMAP 无已知 webmail 时才回退
    /// `message://`（唤起本地邮件客户端，最后兜底）。不再扫描正文 http 链接。
    private static func mailLink(messageId: String, host: String) -> URL? {
        let trimmed = messageId.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        // Gmail：用 Message-ID 打开 Gmail 网页端的原始邮件（不走苹果邮箱 message://）
        if host.lowercased().contains("gmail.com") {
            return URL(string: "https://mail.google.com/mail/u/0/#search/rfc822msgid:\(encoded)")
        }
        // 通用 IMAP 无已知 webmail：不再回退 message://——该 scheme 仅当邮件恰好在本机
        // Mail.app 才打得开，SES/IMAP 邮件点了只会弹「MCMailErrorDomain 1030」。无链接即不显示跳转箭头。
        return nil
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

    /// 明显无效/噪音邮件预过滤（营销 / 退订 / 纯系统通知）：true 表示丢弃，不入库不送 LLM。
    /// 这是「送 AI 之前的一段代码过滤」，避免噪音浪费 token 也刷屏消息页签。
    static func isNoise(domain: String, subject: String) -> Bool {
        let d = domain.lowercased(), s = subject.lowercased()
        let noiseDomains = ["newsletter", "noreply-marketing", "mailchimp", "sendgrid.net",
                            "mailgun", "no-reply@", "donotreply"]
        let noiseWords = ["unsubscribe", "退订", "促销", "newsletter", "广告", "newsletter",
                          "verify your email", "验证码", "对账单", "账单通知", "daily digest"]
        return noiseDomains.contains(where: d.contains) || noiseWords.contains(where: s.contains)
    }

    /// 这些来源已有专属页签，其通知邮件不再进「消息」收件箱，避免与其它页签内容重复：
    /// Jira/Confluence → Mentions 页签；GitHub → Today 的 Jira·GitHub 区。
    static func isCoveredByOtherTab(domain: String, source: MessageSource) -> Bool {
        if source == .jira { return true }              // Jira/Confluence 通知（atlassian.net）
        return domain.lowercased().hasSuffix("github.com")  // GitHub 通知邮件
    }

    // MARK: 非真人自动通知过滤（收件箱只留真人需处理邮件）

    /// 发件地址 localpart 命中自动发件特征（no-reply / notifications / team / mailer …）。
    /// 这是最稳的信号：自动邮件几乎都用这类专用地址，真人邮件极少。
    static func isAutomatedAddress(_ from: String) -> Bool {
        let local = (from.lowercased().split(separator: "@").first.map(String.init) ?? "")
        let markers = ["no-reply", "noreply", "no_reply", "donotreply", "do-not-reply",
                       "notification", "notify", "mailer", "mailer-daemon", "bounce",
                       "automated", "auto-confirm", "newsletter", "digest", "marketing",
                       "updates", "alerts", "account-security", "security-noreply"]
        if markers.contains(where: local.contains) { return true }
        // 纯结构化别名（team/hello/news/info/support/notifications）按整段匹配，避免误伤 teamlead.li 之类
        let exact = ["team", "hello", "news", "info", "support", "notifications", "noreply-marketing"]
        return exact.contains(local)
    }

    /// 主题像「知会/通知/digest/活动/邀请/纪要」这类无需真人回应的内容（地址拿不到时也能判，如已落盘消息）
    static func looksLikeNotificationSubject(_ subject: String) -> Bool {
        let s = subject.lowercased()
        let words = ["digest", "weekly", "newsletter", "changelog", "release note",
                     "what's new", "what’s new", "product update", "activity in",
                     "summary of", "meeting notes", "invitation to", "invited you",
                     "you're invited", "you’re invited", "security alert", "sign-in",
                     "周报", "月报", "更新", "活动", "纪要", "邀请你加入", "受邀", "知会", "通知"]
        return words.contains(where: s.contains)
    }

    /// 收件箱过滤：非真人发来的自动通知/产品更新/营销/系统告警 —— 自动发件地址 或 通知类主题。
    static func isAutomatedNotification(from: String, subject: String) -> Bool {
        isAutomatedAddress(from) || looksLikeNotificationSubject(subject)
    }

    /// 已落盘消息的兜底判定（无原始发件地址，只有展示名 + 原主题）：
    /// 展示名含 no-reply/notifications/team/bot/security/support 等，或主题像通知类。
    static func isAutomatedSenderName(_ name: String, subject: String) -> Bool {
        let n = name.lowercased()
        let nameMarkers = ["no-reply", "noreply", "notification", "notifications", "team",
                           "bot", "security", "support", "mailer", "newsletter", "digest",
                           "do not reply", "automated", "alerts", "no reply"]
        if nameMarkers.contains(where: n.contains) { return true }
        return looksLikeNotificationSubject(subject)
    }
}

// MARK: - 一句话建议的规则化兜底（无 AI Key / AI 失败时使用，不出网）

enum EmailSummary {
    /// ≤20 字一句话建议：发件人 + 主题，超长截断加省略号
    static func suggestion(_ input: EmailDigestInput) -> String {
        let who = input.sender.map { "\($0)：" } ?? ""
        let subject = input.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return clamp("\(who)\(subject.isEmpty ? "新邮件" : subject)")
    }

    /// 硬截断到 20 字（保底，防 AI 超长）
    static func clamp(_ text: String, limit: Int = 20) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > limit ? String(t.prefix(limit - 1)) + "…" : t
    }
}

// MARK: - 重要级别启发式（规则兜底，AI 不可用时用）

enum EmailHeuristics {
    private static let highWords = ["紧急", "尽快", "立即", "马上", "今天", "今晚", "下班前",
                                    "截止", "deadline", "asap", "urgent", "请回复", "等你"]
    private static let lowWords = ["通知", "知会", "fyi", "仅供参考", "已", "周报", "newsletter", "抄送"]
    /// 老板/客户域名提级（可按需扩展）
    private static let importantSenders = ["boss@", "ceo@", "client", "vip"]

    static func importance(_ input: EmailDigestInput) -> MessageImportance {
        let hay = "\(input.sender ?? "") \(input.subject) \(input.bodyExcerpt)".lowercased()
        if importantSenders.contains(where: hay.contains) || highWords.contains(where: hay.contains) {
            return .high
        }
        if lowWords.contains(where: hay.contains) { return .low }
        return .medium
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
            guard !EmailPreprocess.isNoise(domain: domain, subject: subject),
                  !EmailPreprocess.isAutomatedNotification(from: from, subject: subject)
            else { return nil }
            let source = EmailClassifier.source(fromDomain: domain, listId: listId, body: body)
            // 与真实现一致：Jira/Confluence/GitHub 通知邮件不进消息收件箱（已有专属页签）
            guard !EmailPreprocess.isCoveredByOtherTab(domain: domain, source: source) else { return nil }
            return EmailDigestInput(
                messageId: id,
                source: source,
                link: EmailClassifier.normalizedLink(source: source, body: body, messageId: id, host: domain),
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

// MARK: - 真实现：IMAPS（implicit TLS，端口默认 993）

/// 用 Network 框架手写最小 IMAP 客户端（无第三方依赖，沿用项目手写网络层风格）。
/// 凭据来自 settings.emailImapHost / emailAddress / emailAppPassword。
/// 流程：LOGIN → SELECT INBOX → UID SEARCH UNSEEN → 逐封 UID FETCH（头+正文片段）→
/// 来源识别/链接归一/隐私预处理 → EmailDigestInput。失败抛错由装配层静默处理。
@MainActor
final class RealEmailService: EmailService {

    /// 认证方式：基础认证（应用密码）或 OAuth2（O365 必须，token 由 provider 现取现用）
    enum Auth: Sendable {
        case password(String)
        case oauth(@Sendable () async throws -> String)
    }

    private let host: String
    private let port: UInt16
    private let email: String
    private let auth: Auth
    /// 每轮最多处理的未读封数（防一次性拉爆）
    private let maxFetch = 20

    init(host rawHost: String, email: String, auth: Auth) {
        // 支持 "imap.gmail.com" 或 "imap.gmail.com:993"
        let parts = rawHost.split(separator: ":", maxSplits: 1)
        self.host = parts.first.map(String.init) ?? rawHost
        self.port = parts.count == 2 ? (UInt16(parts[1]) ?? 993) : 993
        self.email = email
        self.auth = auth
    }

    /// 便捷构造：应用密码
    convenience init(host: String, email: String, password: String) {
        self.init(host: host, email: email, auth: .password(password))
    }

    func fetchNewMessages() async throws -> [EmailDigestInput] {
        let conn = IMAPConnection(host: host, port: port)
        try await conn.connect()
        defer { conn.close() }

        switch auth {
        case .password(let pw):
            try await conn.login(user: email, password: pw)
        case .oauth(let provider):
            let token = try await provider()
            try await conn.authenticateXOAUTH2(user: email, accessToken: token)
        }
        try await conn.select("INBOX")
        let uids = try await conn.searchUnseen()
        guard !uids.isEmpty else { return [] }

        var out: [EmailDigestInput] = []
        for uid in uids.suffix(maxFetch) {
            guard let raw = try? await conn.fetchMessage(uid: uid) else { continue }
            let domain = raw.from.split(separator: "@").last.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "> ")) } ?? ""
            // 送 AI 之前的一段代码过滤：丢弃明显噪音/无效邮件
            guard !EmailPreprocess.isNoise(domain: domain, subject: raw.subject),
                  // 非真人自动通知/产品更新/营销/系统告警：收件箱只留真人需处理邮件
                  !EmailPreprocess.isAutomatedNotification(from: raw.from, subject: raw.subject)
            else { continue }
            let source = EmailClassifier.source(fromDomain: domain, listId: raw.listId, body: raw.body)
            // Jira/Confluence/GitHub 通知邮件已在 Mentions/Today 呈现，不重复进消息收件箱
            guard !EmailPreprocess.isCoveredByOtherTab(domain: domain, source: source) else { continue }
            let messageId = raw.messageId.isEmpty ? "imap-\(uid)" : raw.messageId
            out.append(EmailDigestInput(
                messageId: messageId,
                source: source,
                link: EmailClassifier.normalizedLink(source: source, body: raw.body, messageId: messageId, host: host),
                sender: raw.displayName.isEmpty ? raw.from : raw.displayName,
                subject: raw.subject,
                bodyExcerpt: EmailPreprocess.excerpt(raw.body),
                receivedAt: raw.date ?? Date()
            ))
        }
        return out
    }
}

// MARK: - 最小 IMAP 连接（NWConnection + TLS，单队列串行驱动）

/// NWConnection 回调在自有串行队列上，方法用 continuation 桥接 async。
/// 标为 @unchecked Sendable：仅经其 queue 访问内部状态。
final class IMAPConnection: @unchecked Sendable {

    struct RawMessage {
        var from = ""        // From 头原始值
        var displayName = "" // From 中的显示名（去引号）
        var subject = ""
        var messageId = ""
        var date: Date?
        var listId: String?
        var body = ""
    }

    private let conn: NWConnection
    private let queue = DispatchQueue(label: "imap.connection")
    private var buffer = Data()
    private var tagSeq = 0

    init(host: String, port: UInt16) {
        let tls = NWProtocolTLS.Options()
        let params = NWParameters(tls: tls)
        conn = NWConnection(host: NWEndpoint.Host(host),
                            port: NWEndpoint.Port(rawValue: port) ?? 993,
                            using: params)
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let e): cont.resume(throwing: e)
                case .waiting(let e): cont.resume(throwing: e)
                default: break
                }
            }
            conn.start(queue: queue)
        }
        conn.stateUpdateHandler = nil
        _ = try await readUntil { $0.hasPrefix("* OK") || $0.contains(" OK ") } // 读问候
    }

    func close() { conn.cancel() }

    // MARK: 命令

    func login(user: String, password: String) async throws {
        _ = try await command("LOGIN \(quoted(user)) \(quoted(password))")
    }

    /// SASL XOAUTH2（O365 OAuth2）：base64("user=<email>^Aauth=Bearer <token>^A^A")，^A=0x01。
    /// 失败时服务器先发 "+" 错误质询，需回空行才拿到 tagged NO，避免挂起。
    func authenticateXOAUTH2(user: String, accessToken: String) async throws {
        let sasl = "user=\(user)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        let b64 = Data(sasl.utf8).base64EncodedString()
        let tag = nextTag()
        try await send("\(tag) AUTHENTICATE XOAUTH2 \(b64)\r\n")
        var resp = try await readUntil { $0.hasPrefix("\(tag) ") || $0.hasPrefix("+") }
        if resp.split(separator: "\r\n").contains(where: { $0.hasPrefix("+") }) {
            // 错误质询：回空行触发服务器返回 tagged 结果
            try await send("\r\n")
            resp = try await readUntil { $0.hasPrefix("\(tag) ") }
        }
        if let line = resp.split(separator: "\r\n").first(where: {
            $0.hasPrefix("\(tag) NO") || $0.hasPrefix("\(tag) BAD")
        }) {
            let reason = String(line.dropFirst(tag.count + 1)).trimmingCharacters(in: .whitespaces)
            NSLog("[IMAP] XOAUTH2 rejected: \(reason)")
            throw EmailServiceError.server(reason)
        }
    }

    func select(_ mailbox: String) async throws {
        _ = try await command("SELECT \(quoted(mailbox))")
    }

    /// UID SEARCH UNSEEN → 未读 UID 列表
    func searchUnseen() async throws -> [Int] {
        let resp = try await command("UID SEARCH UNSEEN")
        guard let line = resp.split(separator: "\r\n").first(where: { $0.uppercased().contains("SEARCH") }) else { return [] }
        return line.split(separator: " ").compactMap { Int($0) }
    }

    /// 单封 UID FETCH：头字段 + 正文前 2KB（隐私截断也对齐）
    func fetchMessage(uid: Int) async throws -> RawMessage {
        let resp = try await command(
            "UID FETCH \(uid) (BODY.PEEK[HEADER.FIELDS (FROM SUBJECT MESSAGE-ID DATE LIST-ID)] BODY.PEEK[TEXT]<0.2048>)"
        )
        return Self.parse(resp)
    }

    // MARK: 收发

    private func nextTag() -> String { tagSeq += 1; return "A\(tagSeq)" }

    /// 发带 tag 命令并读到该 tag 的完成行（OK/NO/BAD）；NO/BAD 抛错
    private func command(_ cmd: String) async throws -> String {
        let tag = nextTag()
        try await send("\(tag) \(cmd)\r\n")
        let resp = try await readUntil { line in
            line.hasPrefix("\(tag) OK") || line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD")
        }
        // 取该 tag 的完成行原文（NO/BAD 时含服务器拒绝原因）
        if let line = resp.split(separator: "\r\n").first(where: {
            $0.hasPrefix("\(tag) NO") || $0.hasPrefix("\(tag) BAD")
        }) {
            let reason = String(line.dropFirst(tag.count + 1)).trimmingCharacters(in: .whitespaces)
            NSLog("[IMAP] command rejected: \(reason)")
            throw EmailServiceError.server(reason)
        }
        return resp
    }

    private func send(_ string: String) async throws {
        let data = Data(string.utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    /// 持续接收直到某一行满足 done（用 latin1 保留字节，便于含中文 base64 头解析）
    private func readUntil(done: @escaping (String) -> Bool) async throws -> String {
        while true {
            let text = String(decoding: buffer, as: UTF8.self)
            if text.split(separator: "\r\n").contains(where: { done(String($0)) }) {
                buffer.removeAll()
                return text
            }
            let chunk = try await receiveChunk()
            guard !chunk.isEmpty else {
                let text = String(decoding: buffer, as: UTF8.self); buffer.removeAll(); return text
            }
            buffer.append(chunk)
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: data ?? Data())
            }
        }
    }

    private func quoted(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    // MARK: 解析（容错：从 FETCH 响应里抽头字段与正文）

    private static func parse(_ resp: String) -> RawMessage {
        var msg = RawMessage()
        // 头字段（可能 MIME 编码，做轻量 RFC2047 解码）
        for line in resp.split(separator: "\r\n") {
            let l = String(line)
            if let v = headerValue(l, "From:") { msg.from = decodeMIME(v); msg.displayName = displayName(from: msg.from) }
            else if let v = headerValue(l, "Subject:") { msg.subject = decodeMIME(v) }
            else if let v = headerValue(l, "Message-ID:") { msg.messageId = v.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")) }
            else if let v = headerValue(l, "List-ID:") { msg.listId = v }
            else if let v = headerValue(l, "Date:") { msg.date = parseDate(v) }
        }
        // 正文：取最后一个字面量块（BODY[TEXT] 的内容）
        if let body = lastLiteral(in: resp) { msg.body = body }
        return msg
    }

    private static func headerValue(_ line: String, _ field: String) -> String? {
        guard line.lowercased().hasPrefix(field.lowercased()) else { return nil }
        return String(line.dropFirst(field.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func displayName(from: String) -> String {
        if let lt = from.firstIndex(of: "<") {
            let name = from[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            if !name.isEmpty { return name }
        }
        return from.split(separator: "@").first.map(String.init) ?? from
    }

    /// 抓取 `{n}\r\n` 字面量后的 n 字节内容；取最后一个（正文 TEXT）
    private static func lastLiteral(in resp: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\{(\d+)\}\r\n"#) else { return nil }
        let ns = resp as NSString
        let matches = regex.matches(in: resp, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last, let n = Int(ns.substring(with: last.range(at: 1))) else { return nil }
        let start = last.range.location + last.range.length
        let len = min(n, ns.length - start)
        guard len > 0 else { return nil }
        return ns.substring(with: NSRange(location: start, length: len))
    }

    /// 轻量 RFC2047：=?UTF-8?B?..?= / =?UTF-8?Q?..?=（覆盖中文主题常见编码）
    private static func decodeMIME(_ raw: String) -> String {
        guard raw.contains("=?"), let regex = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#) else { return raw }
        let ns = raw as NSString
        var result = raw
        for m in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)).reversed() {
            let enc = ns.substring(with: m.range(at: 2)).uppercased()
            let payload = ns.substring(with: m.range(at: 3))
            var decoded: String?
            if enc == "B" {
                if let d = Data(base64Encoded: payload) { decoded = String(data: d, encoding: .utf8) }
            } else { // Q
                let qp = payload.replacingOccurrences(of: "_", with: " ")
                decoded = decodeQuotedPrintable(qp)
            }
            if let decoded { result = (result as NSString).replacingCharacters(in: m.range, with: decoded) }
        }
        return result
    }

    private static func decodeQuotedPrintable(_ s: String) -> String? {
        var bytes = [UInt8](); let chars = Array(s); var i = 0
        while i < chars.count {
            if chars[i] == "=", i + 2 < chars.count, let b = UInt8(String(chars[i+1...i+2]), radix: 16) {
                bytes.append(b); i += 3
            } else { bytes.append(contentsOf: Array(String(chars[i]).utf8)); i += 1 }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return f
    }()
    private static func parseDate(_ s: String) -> Date? {
        rfc822.date(from: s.trimmingCharacters(in: .whitespaces))
    }
}
