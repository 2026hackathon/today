import Foundation

// ============================================================
// AIService —— AI 解析链路协议 + Mock + Anthropic 骨架。
// Owner: B
//
// 接真实现步骤（B）：
// 1. 在 AnthropicAIService 中用 settings.aiAPIKey 调 Anthropic Messages API
//    （vision 传 base64 图片，文本走普通 messages）。
// 2. 输出约定 JSON schema → 解析为 [TodoDraft]。
// 3. AppDelegate 装配处把 MockAIService 换成 AnthropicAIService(apiKey:)。
//    注意：保留 MockAIService 不要删（CODING_GUIDELINES：Demo 兜底）。
// ============================================================

enum AIServiceError: Error {
    /// 真实现尚未接入
    case notImplemented
    /// 未配置 API Key
    case notConfigured
    /// LLM 返回无法解析
    case invalidResponse
}

@MainActor
protocol AIService: AnyObject {
    /// 截图 → 草稿列表。1 个 = newTask 单卡；≥3 个 = batch 批量卡（ai-pipeline spec）
    func parseScreenshot(_ imageData: Data) async throws -> [TodoDraft]
    /// 自然语言一句话 → 单个草稿（⌘N 快速输入）
    func parseQuickInput(_ text: String) async throws -> TodoDraft
    func generateMorningReport(_ ctx: ReportContext) async throws -> String
    func generateEveningReport(_ ctx: ReportContext) async throws -> String
}

// MARK: - Mock 实现（固定延迟 ~1.2s，永不失败 —— ai-pipeline spec）

@MainActor
final class MockAIService: AIService {

    /// Demo 开关：true 时 parseScreenshot 返回 5 条会议纪要 drafts（批量识别演示）
    var batchMode = false

    init() {}

    // MARK: 截图解析

    func parseScreenshot(_ imageData: Data) async throws -> [TodoDraft] {
        try? await Task.sleep(for: .seconds(1.2)) // 模拟网络延迟
        if batchMode {
            return Self.meetingNotesDrafts()
        }
        let cal = Calendar.current
        let tonight = cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date())
        return [
            TodoDraft(
                title: "完成首页性能优化",
                source: .screenshot,
                priority: .high,
                dueDate: tonight,
                aiExplanation: "检测到「本周内」关键词，推断为今晚截止"
            )
        ]
    }

    /// 5 条会议纪要 drafts：前 3 条默认勾选，后 2 条不勾选，截止时间错开
    private static func meetingNotesDrafts() -> [TodoDraft] {
        let cal = Calendar.current
        let now = Date()
        func day(_ offset: Int, hour: Int) -> Date? {
            guard let d = cal.date(byAdding: .day, value: offset, to: now) else { return nil }
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d)
        }
        return [
            TodoDraft(title: "陈昊跟进 API 设计文档", source: .screenshot, priority: .high,
                      dueDate: day(0, hour: 18),
                      aiExplanation: "会议纪要中标注「今天给结论」", isSelected: true),
            TodoDraft(title: "林嘉完成前端原型", source: .screenshot, priority: .medium,
                      dueDate: day(1, hour: 12),
                      aiExplanation: "纪要约定明天中午前提交", isSelected: true),
            TodoDraft(title: "周彦约客户沟通", source: .screenshot, priority: .medium,
                      dueDate: day(1, hour: 18),
                      aiExplanation: "需在客户下班前敲定时间", isSelected: true),
            TodoDraft(title: "全员评审 PRD", source: .screenshot, priority: .medium,
                      dueDate: day(2, hour: 15),
                      aiExplanation: "评审会定在后天下午", isSelected: false),
            TodoDraft(title: "部署测试环境", source: .screenshot, priority: .low,
                      dueDate: day(3, hour: 18),
                      aiExplanation: "依赖评审通过后执行", isSelected: false),
        ]
    }

    // MARK: 快速输入解析（简单规则）

    func parseQuickInput(_ text: String) async throws -> TodoDraft {
        try? await Task.sleep(for: .seconds(1.2)) // 模拟网络延迟
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.current
        let now = Date()
        var explanations: [String] = []

        // 「X点」→ 该小时
        var parsedHour: Int?
        if let match = trimmed.firstMatch(of: #/(\d{1,2})\s*点/#),
           let h = Int(match.1), (0...23).contains(h) {
            parsedHour = h
            explanations.append("检测到「\(h)点」")
        }

        // 日期关键词
        var dueDate: Date?
        if trimmed.contains("明天") {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
            dueDate = cal.date(bySettingHour: parsedHour ?? 18, minute: 0, second: 0, of: tomorrow)
            explanations.append("检测到「明天」关键词")
        } else if trimmed.contains("今晚") || trimmed.contains("今天") {
            dueDate = cal.date(bySettingHour: parsedHour ?? 18, minute: 0, second: 0, of: now)
            explanations.append("检测到「今晚/今天」→ 今天 \(parsedHour ?? 18):00")
        } else if let h = parsedHour {
            // 只有小时无日期：默认今天该小时；已过则顺延到明天
            var candidate = cal.date(bySettingHour: h, minute: 0, second: 0, of: now)
            if let c = candidate, c < now {
                candidate = cal.date(byAdding: .day, value: 1, to: c)
                explanations.append("\(h)点已过，顺延到明天")
            }
            dueDate = candidate
        }

        // 优先级：紧急关键词 或 24h 内截止 → high
        var priority: Priority = .medium
        let lower = trimmed.lowercased()
        if trimmed.contains("紧急") || trimmed.contains("立即") || lower.contains("asap") {
            priority = .high
            explanations.append("含「紧急/ASAP/立即」关键词 → 高优先级")
        } else if let due = dueDate, due.timeIntervalSince(now) < 24 * 3600 {
            priority = .high
            explanations.append("24 小时内截止 → 高优先级")
        }

        return TodoDraft(
            title: trimmed.isEmpty ? "新任务" : trimmed,
            source: .manual,
            priority: priority,
            dueDate: dueDate,
            aiExplanation: explanations.isEmpty ? nil : explanations.joined(separator: "；")
        )
    }

    // MARK: 晨报 / 晚报（中文 markdown，结构：问候/优先处理/今日会议/个人 Todo/Jira/建议）

    func generateMorningReport(_ ctx: ReportContext) async throws -> String {
        try? await Task.sleep(for: .seconds(1.2))
        var md = "# ☀️ 早安！\n\n"
        md += "今天是 \(Self.dateLine(ctx.date))，你有 \(ctx.pendingTodos.count) 个待办、\(ctx.meetings.count) 场会议。\n\n"

        let priorities = ctx.pendingTodos
            .sorted {
                if $0.priority.sortRank != $1.priority.sortRank { return $0.priority.sortRank < $1.priority.sortRank }
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            .prefix(3)
        md += "## 🔥 优先处理\n"
        if priorities.isEmpty {
            md += "- 暂无待办，享受轻松的一天\n"
        } else {
            for todo in priorities {
                md += "- **\(todo.title)**\(Self.dueSuffix(todo.dueDate))"
                if let why = todo.aiExplanation { md += " — \(why)" }
                md += "\n"
            }
        }

        md += "\n## 📅 今日会议\n"
        let meetings = ctx.meetings.sorted { $0.start < $1.start }
        if meetings.isEmpty {
            md += "- 今天没有会议\n"
        } else {
            for m in meetings {
                md += "- \(Self.time(m.start))–\(Self.time(m.end)) \(m.title)"
                if let p = m.platform { md += "（\(p.label)）" }
                md += "\n"
            }
        }

        md += "\n## ✅ 个人 Todo\n"
        let personal = ctx.pendingTodos.filter { $0.source != .jira }
        md += personal.isEmpty ? "- 无\n" : personal.map { "- \($0.title)\(Self.dueSuffix($0.dueDate))" }.joined(separator: "\n") + "\n"

        md += "\n## 🧩 Jira\n"
        let jira = ctx.pendingTodos.filter { $0.source == .jira }
        md += jira.isEmpty ? "- 无指派 ticket\n" : jira.map { "- \($0.jiraKey ?? "") \($0.title)（\($0.jiraStatus ?? "To Do")）" }.joined(separator: "\n") + "\n"

        md += "\n## 💡 建议\n"
        if let first = priorities.first {
            md += "- 建议先完成「\(first.title)」，避免高优任务挤压下午时间\n"
        }
        if !meetings.isEmpty {
            md += "- 会前 10 分钟留出准备时间，会议间隙处理小任务\n"
        }
        md += "- 上午精力最好，安排深度工作；琐事放到午后\n"
        return md
    }

    func generateEveningReport(_ ctx: ReportContext) async throws -> String {
        try? await Task.sleep(for: .seconds(1.2))
        var md = "# 🌙 晚上好，来复盘今天\n\n"
        md += "\(Self.dateLine(ctx.date))，完成 \(ctx.completedToday.count) 项，剩余 \(ctx.pendingTodos.count) 项待办。\n\n"

        md += "## 🎉 今日完成\n"
        md += ctx.completedToday.isEmpty
            ? "- 今天还没有完成记录\n"
            : ctx.completedToday.map { "- ~~\($0.title)~~" }.joined(separator: "\n") + "\n"

        md += "\n## 🔥 优先处理（结转明天）\n"
        let carry = ctx.pendingTodos
            .sorted {
                if $0.priority.sortRank != $1.priority.sortRank { return $0.priority.sortRank < $1.priority.sortRank }
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            .prefix(3)
        md += carry.isEmpty ? "- 全部清空，太棒了！\n" : carry.map { "- **\($0.title)**\(Self.dueSuffix($0.dueDate))" }.joined(separator: "\n") + "\n"

        md += "\n## 📅 今日会议\n"
        md += ctx.meetings.isEmpty ? "- 今天没有会议\n" : ctx.meetings.map { "- \(Self.time($0.start)) \($0.title)" }.joined(separator: "\n") + "\n"

        md += "\n## 🧩 Jira\n"
        let jira = ctx.pendingTodos.filter { $0.source == .jira }
        md += jira.isEmpty ? "- 无未完成 ticket\n" : jira.map { "- \($0.jiraKey ?? "") \($0.title)（\($0.jiraStatus ?? "To Do")）" }.joined(separator: "\n") + "\n"

        md += "\n## 💡 建议\n"
        if let first = carry.first {
            md += "- 把「\(first.title)」排到明早第一件事，趁精力最好时啃硬骨头\n"
        }
        md += "- 睡前列好明日三件要事，今晚好好休息 💤\n"
        return md
    }

    // MARK: 格式化辅助

    private static let dateLineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static func dateLine(_ date: Date) -> String { dateLineFormatter.string(from: date) }
    private static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    private static func dueSuffix(_ due: Date?) -> String {
        guard let due else { return "" }
        if Calendar.current.isDateInToday(due) { return "（今天 \(time(due)) 截止）" }
        if Calendar.current.isDateInTomorrow(due) { return "（明天 \(time(due)) 截止）" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return "（\(f.string(from: due)) 截止）"
    }
}

// MARK: - Anthropic 真实现骨架（B 接管）

@MainActor
final class AnthropicAIService: AIService {

    private let apiKey: String

    /// - Parameter apiKey: 来自 settings.aiAPIKey（AppDelegate 装配时传入）
    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func parseScreenshot(_ imageData: Data) async throws -> [TodoDraft] {
        guard !apiKey.isEmpty else { throw AIServiceError.notConfigured }
        // TODO: B 接真实 LLM 调用
        // 1. imageData → base64，构造 Anthropic Messages API vision 请求
        // 2. system prompt 要求输出 JSON 数组 [{title, priority, dueDate, aiExplanation}]
        // 3. JSONDecoder 解析 → [TodoDraft]（失败 throw .invalidResponse）
        throw AIServiceError.notImplemented
    }

    func parseQuickInput(_ text: String) async throws -> TodoDraft {
        guard !apiKey.isEmpty else { throw AIServiceError.notConfigured }
        // TODO: B 接真实 LLM 调用（文本 → 单个 TodoDraft JSON）
        throw AIServiceError.notImplemented
    }

    func generateMorningReport(_ ctx: ReportContext) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.notConfigured }
        // TODO: B 接真实 LLM 调用（ctx 序列化进 prompt，要求中文 markdown 晨报）
        throw AIServiceError.notImplemented
    }

    func generateEveningReport(_ ctx: ReportContext) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.notConfigured }
        // TODO: B 接真实 LLM 调用（ctx 序列化进 prompt，要求中文 markdown 晚报）
        throw AIServiceError.notImplemented
    }
}
