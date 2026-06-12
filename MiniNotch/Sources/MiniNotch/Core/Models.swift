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
        jiraAssigner: String? = nil, storyPoints: Double? = nil,
        aiExplanation: String? = nil, tags: [String] = []
    ) {
        self.id = id; self.title = title; self.note = note
        self.source = source; self.priority = priority
        self.dueDate = dueDate; self.createdAt = createdAt; self.completedAt = completedAt
        self.snoozedUntil = snoozedUntil; self.snoozeCount = snoozeCount
        self.screenshotPath = screenshotPath
        self.jiraKey = jiraKey; self.jiraURL = jiraURL; self.jiraStatus = jiraStatus
        self.jiraAssigner = jiraAssigner; self.storyPoints = storyPoints
        self.aiExplanation = aiExplanation; self.tags = tags
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
        jiraAssigner = try? c.decodeIfPresent(String.self, forKey: .jiraAssigner)
        storyPoints = try? c.decodeIfPresent(Double.self, forKey: .storyPoints)
        aiExplanation = try? c.decodeIfPresent(String.self, forKey: .aiExplanation)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
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

    enum Status { case upcoming, ongoing, ended }

    var status: Status {
        if isReminder { return .upcoming } // 提醒事项不参与 ongoing/ended 判断
        let now = Date()
        if now < start { return .upcoming }
        if now > end { return .ended }
        return .ongoing
    }
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
    }

    func isQuietHour(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        if quietHourStart > quietHourEnd {
            return hour >= quietHourStart || hour < quietHourEnd
        }
        return hour >= quietHourStart && hour < quietHourEnd
    }
}
