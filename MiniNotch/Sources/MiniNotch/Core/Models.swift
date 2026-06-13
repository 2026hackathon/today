import Foundation

// ============================================================
// 核心数据模型 —— 全员共享契约。
// 改字段必须先开 openspec change 并通知全员（见 docs/MODULES.md）。
// ============================================================

// MARK: - 枚举

enum Priority: String, Codable, CaseIterable, Sendable {
    case high, medium, low

    /// 列表排序权重（越小越靠前）
    var sortRank: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    var label: String {
        switch self {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        }
    }
}

/// 任务来源 —— 决定 Touchdown 动效的涟漪颜色（见 DesignTokens.sourceColor）
enum TodoSource: String, Codable, CaseIterable, Sendable {
    case screenshot, jira, manual, calendar, wechat, github

    var label: String {
        switch self {
        case .screenshot: "截图"
        case .jira: "Jira"
        case .manual: "手动"
        case .calendar: "日历"
        case .wechat: "微信"
        case .github: "GitHub"
        }
    }
}

/// 消息来源（email-integration spec）—— 决定链接归一与来源标识/配色
enum MessageSource: String, Codable, CaseIterable, Sendable {
    case slack, jira, email

    var label: String {
        switch self {
        case .slack: "Slack"
        case .jira: "Jira"
        case .email: "邮件"
        }
    }

    /// 来源 SF Symbol（消息卡/页签行图标）
    var iconSymbol: String {
        switch self {
        case .slack: "number.square.fill"
        case .jira: "briefcase.fill"
        case .email: "envelope.fill"
        }
    }
}

enum MeetingPlatform: String, Codable, CaseIterable, Sendable {
    case zoom, tencent, googleMeet, teams, feishu, dingtalk, other

    var label: String {
        switch self {
        case .zoom: "Zoom"
        case .tencent: "腾会"
        case .googleMeet: "Meet"
        case .teams: "Teams"
        case .feishu: "飞书"
        case .dingtalk: "钉钉"
        case .other: "会议"
        }
    }
}

/// 提醒分级（reminders spec）
enum ReminderLevel: String, Codable, Sendable {
    case oneHour      // 提前 1h，弱
    case fifteenMin   // 提前 15min，中
    case due          // 到期，强
    case overdue      // 已过期，极强
}

// MARK: - Todo

struct Todo: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var note: String?
    var source: TodoSource = .manual
    var priority: Priority = .medium
    var dueDate: Date?
    var createdAt = Date()
    var completedAt: Date?
    var snoozedUntil: Date?
    var snoozeCount = 0
    /// 原始截图文件路径（截图来源时有值）
    var screenshotPath: String?
    var jiraKey: String?
    var jiraURL: URL?
    var jiraStatus: String?
    /// Jira statusCategory.key（"new" / "indeterminate" / "done"），
    /// 机器值不随站点语言变化 —— 活跃判断用它，status.name 仅展示
    var jiraStatusCategory: String?
    /// 最近一次把 ticket 指派给我的人（来自 changelog，可能是自己）
    var jiraAssigner: String?
    /// Story Points（Jira custom field，wonder 站点为 customfield_10025）
    var storyPoints: Double?
    /// AI 紧急度判断依据，如「检测到『今晚之前』关键词」
    var aiExplanation: String?
    var tags: [String] = []
    /// 日历/提醒来源的 EventKit 稳定标识（合并同步与日历页签完成状态匹配的键）
    var calendarEventId: String?

    var isCompleted: Bool { completedAt != nil }

    /// 超期锚点 = snoozedUntil ?? dueDate（review-fixes #9）：
    /// snooze 到未来 → 不超期、回「今日任务」；snooze 过期才重新计超期
    var isOverdue: Bool {
        guard !isCompleted, let anchor = snoozedUntil ?? dueDate else { return false }
        return anchor < Date()
    }

    /// "3 SP" / "0.5 SP"（整数去掉小数点）
    var storyPointsLabel: String? {
        guard let sp = storyPoints else { return nil }
        return sp == sp.rounded() ? "\(Int(sp)) SP" : "\(sp) SP"
    }

    init(
        id: UUID = UUID(), title: String, note: String? = nil,
        source: TodoSource = .manual, priority: Priority = .medium,
        dueDate: Date? = nil, createdAt: Date = Date(), completedAt: Date? = nil,
        snoozedUntil: Date? = nil, snoozeCount: Int = 0, screenshotPath: String? = nil,
        jiraKey: String? = nil, jiraURL: URL? = nil, jiraStatus: String? = nil,
        jiraStatusCategory: String? = nil,
        jiraAssigner: String? = nil, storyPoints: Double? = nil,
        aiExplanation: String? = nil, tags: [String] = [],
        calendarEventId: String? = nil
    ) {
        self.id = id; self.title = title; self.note = note
        self.source = source; self.priority = priority
        self.dueDate = dueDate; self.createdAt = createdAt; self.completedAt = completedAt
        self.snoozedUntil = snoozedUntil; self.snoozeCount = snoozeCount
        self.screenshotPath = screenshotPath
        self.jiraKey = jiraKey; self.jiraURL = jiraURL; self.jiraStatus = jiraStatus
        self.jiraStatusCategory = jiraStatusCategory
        self.jiraAssigner = jiraAssigner; self.storyPoints = storyPoints
        self.aiExplanation = aiExplanation; self.tags = tags
        self.calendarEventId = calendarEventId
    }

    /// 向后兼容解码（review-fixes #4）：合成 Codable 不会用属性默认值兜底，
    /// 任何人加一个字段都会让旧 todos.json 整体解码失败 → 被空数组覆盖 → 数据丢失。
    /// 这里逐字段 decodeIfPresent，缺失/类型不符取默认值。改字段记得同步这里。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        source = (try? c.decodeIfPresent(TodoSource.self, forKey: .source)) ?? .manual
        priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? .medium
        dueDate = try? c.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        snoozedUntil = try? c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        snoozeCount = (try? c.decodeIfPresent(Int.self, forKey: .snoozeCount)) ?? 0
        screenshotPath = try? c.decodeIfPresent(String.self, forKey: .screenshotPath)
        jiraKey = try? c.decodeIfPresent(String.self, forKey: .jiraKey)
        jiraURL = try? c.decodeIfPresent(URL.self, forKey: .jiraURL)
        jiraStatus = try? c.decodeIfPresent(String.self, forKey: .jiraStatus)
        jiraStatusCategory = try? c.decodeIfPresent(String.self, forKey: .jiraStatusCategory)
        jiraAssigner = try? c.decodeIfPresent(String.self, forKey: .jiraAssigner)
        storyPoints = try? c.decodeIfPresent(Double.self, forKey: .storyPoints)
        aiExplanation = try? c.decodeIfPresent(String.self, forKey: .aiExplanation)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        calendarEventId = try? c.decodeIfPresent(String.self, forKey: .calendarEventId)
    }
}

// MARK: - TodoDraft（AI 解析的中间产物，用户确认后转 Todo）

struct TodoDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var note: String?
    var source: TodoSource = .screenshot
    var priority: Priority = .medium
    var dueDate: Date?
    var aiExplanation: String?
    var screenshotPath: String?
    /// 批量识别卡片中是否勾选
    var isSelected = true
    /// 周期标签（如「每天」「每周一」），AI 解析或手动添加；完成时据此自动排下一次
    var tags: [String] = []

    func toTodo() -> Todo {
        Todo(
            title: title, note: note, source: source, priority: priority,
            dueDate: dueDate, screenshotPath: screenshotPath,
            aiExplanation: aiExplanation, tags: tags
        )
    }
}

// MARK: - Meeting

struct Meeting: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var link: URL?
    var platform: MeetingPlatform?
    var attendees: [String] = []
    var calendarName: String?
    /// 是否来自「提醒事项」（true 时 link/platform 通常为 nil，UI 用不同样式渲染）
    var isReminder: Bool = false
    /// EventKit 稳定标识（EKEvent.eventIdentifier / EKReminder.calendarItemIdentifier），
    /// .calendar 任务合并与完成状态匹配的键；演示数据为 nil（不入任务）
    var eventIdentifier: String? = nil
    /// 全天事件 / 无具体时间的提醒（对应任务落「无固定时间」分区，不按时间排）
    var isAllDay: Bool = false
    /// 提醒事项在 EventKit 中的完成态（日历事件恒 false）——
    /// 已完成提醒保留在日历页签并打勾，外部勾选经合并同步进本地任务
    var isCompleted: Bool = false

    enum Status { case upcoming, ongoing, ended }

    var status: Status {
        if isReminder { return .upcoming } // 提醒事项不参与 ongoing/ended 判断
        let now = Date()
        if now < start { return .upcoming }
        if now > end { return .ended }
        return .ongoing
    }
}

/// 向后兼容解码（与 Todo 同理）：合成 Codable 不用属性默认值兜底，
/// 新增非可选字段会让旧 meetings.json 整体解码失败。放 extension 里保留合成 memberwise init。
extension Meeting {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        start = (try? c.decodeIfPresent(Date.self, forKey: .start)) ?? Date()
        end = (try? c.decodeIfPresent(Date.self, forKey: .end)) ?? start
        link = try? c.decodeIfPresent(URL.self, forKey: .link)
        platform = try? c.decodeIfPresent(MeetingPlatform.self, forKey: .platform)
        attendees = (try? c.decodeIfPresent([String].self, forKey: .attendees)) ?? []
        calendarName = try? c.decodeIfPresent(String.self, forKey: .calendarName)
        isReminder = (try? c.decodeIfPresent(Bool.self, forKey: .isReminder)) ?? false
        eventIdentifier = try? c.decodeIfPresent(String.self, forKey: .eventIdentifier)
        isAllDay = (try? c.decodeIfPresent(Bool.self, forKey: .isAllDay)) ?? false
        isCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
    }
}

// MARK: - Message（邮件提炼的一句话提醒，message-inbox spec）

/// 独立于 Todo：邮件消息有自己的「已处理/未处理」生命周期，持久化到 messages.json。
struct Message: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    /// 邮件 Message-ID —— addMessages 去重键（Mock 用合成值）
    var messageId: String
    /// AI 一句话提醒（who + 要点 + 可选时间）
    var summary: String
    var source: MessageSource = .email
    /// 可点击跳转链接：slack 深链 / jira issue / 邮件链接（email-integration spec）
    var link: URL?
    var receivedAt = Date()
    /// nil = 未处理（白）；非 nil = 已处理（灰）
    var processedAt: Date?
    var sender: String?
    var rawSubject: String?

    var isProcessed: Bool { processedAt != nil }

    init(
        id: UUID = UUID(), messageId: String, summary: String,
        source: MessageSource = .email, link: URL? = nil,
        receivedAt: Date = Date(), processedAt: Date? = nil,
        sender: String? = nil, rawSubject: String? = nil
    ) {
        self.id = id; self.messageId = messageId; self.summary = summary
        self.source = source; self.link = link
        self.receivedAt = receivedAt; self.processedAt = processedAt
        self.sender = sender; self.rawSubject = rawSubject
    }

    /// 向后兼容解码（与 Todo/Meeting 同理）：逐字段 decodeIfPresent，缺失取默认
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        messageId = (try? c.decodeIfPresent(String.self, forKey: .messageId)) ?? ""
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        source = (try? c.decodeIfPresent(MessageSource.self, forKey: .source)) ?? .email
        link = try? c.decodeIfPresent(URL.self, forKey: .link)
        receivedAt = (try? c.decodeIfPresent(Date.self, forKey: .receivedAt)) ?? Date()
        processedAt = try? c.decodeIfPresent(Date.self, forKey: .processedAt)
        sender = try? c.decodeIfPresent(String.self, forKey: .sender)
        rawSubject = try? c.decodeIfPresent(String.self, forKey: .rawSubject)
    }
}

/// 待 AI 摘要的邮件输入（email-integration spec）：EmailService 完成来源识别 /
/// 链接归一 / 隐私预处理后产出，AppDelegate 调 AIService 生成 summary 再组装 Message。
struct EmailDigestInput: Sendable {
    var messageId: String
    var source: MessageSource
    var link: URL?
    var sender: String?
    var subject: String
    /// 已截断 / 剥离签名与引用历史后的正文片段（隐私预处理产物）
    var bodyExcerpt: String
    var receivedAt: Date
}

// MARK: - 晨报/晚报上下文（ai-pipeline spec）

struct ReportContext: Sendable {
    var pendingTodos: [Todo]
    var completedToday: [Todo]
    var meetings: [Meeting]
    var date = Date()
}

// MARK: - 应用设置

struct AppSettings: Codable, Equatable, Sendable {
    /// 勿扰时段（小时，22 → 22:00）
    var quietHourStart = 22
    var quietHourEnd = 8
    /// 晚报触发时间
    var eveningReportHour = 18
    /// 装饰性动效开关（撒花/烟花/流光）
    var effectsEnabled = true
    /// AI 配置：OpenAI 兼容端点（Azure Foundry 的 .../openai/v1 也行）；Key 为空走 Mock
    var aiAPIKey = ""
    var aiBaseURL = ""
    /// 模型/部署名（Azure 上必须是部署名，例如 gpt-5.5）
    var aiModel = ""
    /// Jira 配置（C 接真实现后使用）
    var jiraBaseURL = ""
    var jiraEmail = ""
    var jiraAPIToken = ""
    /// Jira 轮询间隔（秒），设置面板可调，下个轮询周期生效（GitHub 共用）
    var jiraPollSeconds = 60
    /// GitHub Personal Access Token（拉取待我 review / 指派给我的 PR；空走 Mock）
    var githubToken = ""
    /// 飞书 webhook / Bark 推送
    var feishuWebhook = ""
    var barkToken = ""
    /// 邮件接入（email-integration spec）：三项齐全 → RealEmailService(IMAP)，否则 Mock。
    /// 密码本期入 settings.json，后续升级 Keychain（design D7）
    var emailAddress = ""
    var emailImapHost = ""
    var emailAppPassword = ""

    init() {}

    /// 向后兼容解码：新增字段在旧 settings.json 里缺失时取默认值。
    /// 不写这个的话，加任何新字段都会让整个解码失败 → 用户已配置的 Jira/Key 全部丢失
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quietHourStart = try c.decodeIfPresent(Int.self, forKey: .quietHourStart) ?? 22
        quietHourEnd = try c.decodeIfPresent(Int.self, forKey: .quietHourEnd) ?? 8
        eveningReportHour = try c.decodeIfPresent(Int.self, forKey: .eveningReportHour) ?? 18
        effectsEnabled = try c.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? true
        aiAPIKey = try c.decodeIfPresent(String.self, forKey: .aiAPIKey) ?? ""
        aiBaseURL = try c.decodeIfPresent(String.self, forKey: .aiBaseURL) ?? ""
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? ""
        jiraBaseURL = try c.decodeIfPresent(String.self, forKey: .jiraBaseURL) ?? ""
        jiraEmail = try c.decodeIfPresent(String.self, forKey: .jiraEmail) ?? ""
        jiraAPIToken = try c.decodeIfPresent(String.self, forKey: .jiraAPIToken) ?? ""
        jiraPollSeconds = try c.decodeIfPresent(Int.self, forKey: .jiraPollSeconds) ?? 60
        githubToken = try c.decodeIfPresent(String.self, forKey: .githubToken) ?? ""
        feishuWebhook = try c.decodeIfPresent(String.self, forKey: .feishuWebhook) ?? ""
        barkToken = try c.decodeIfPresent(String.self, forKey: .barkToken) ?? ""
        emailAddress = try c.decodeIfPresent(String.self, forKey: .emailAddress) ?? ""
        emailImapHost = try c.decodeIfPresent(String.self, forKey: .emailImapHost) ?? ""
        emailAppPassword = try c.decodeIfPresent(String.self, forKey: .emailAppPassword) ?? ""
    }

    func isQuietHour(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        if quietHourStart > quietHourEnd {
            return hour >= quietHourStart || hour < quietHourEnd
        }
        return hour >= quietHourStart && hour < quietHourEnd
    }
}
