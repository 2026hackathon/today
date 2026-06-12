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
    case screenshot, jira, manual, calendar, wechat

    var label: String {
        switch self {
        case .screenshot: "截图"
        case .jira: "Jira"
        case .manual: "手动"
        case .calendar: "日历"
        case .wechat: "微信"
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
    /// AI 紧急度判断依据，如「检测到『今晚之前』关键词」
    var aiExplanation: String?
    var tags: [String] = []

    var isCompleted: Bool { completedAt != nil }

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Date()
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

    enum Status { case upcoming, ongoing, ended }

    var status: Status {
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
    /// Jira 轮询间隔（秒），设置面板可调，下个轮询周期生效
    var jiraPollSeconds = 60
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
