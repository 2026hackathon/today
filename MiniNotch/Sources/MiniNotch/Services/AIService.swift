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
    /// 一句话行动建议（Today 面板底部建议条，30 字内）
    func generateDailySuggestion(_ ctx: ReportContext) async throws -> String
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

        var dueDate: Date?

        // ── 相对时间：「N分钟后 / N(个)小时后 / 半小时后」优先级最高 ──
        if let match = trimmed.firstMatch(of: #/(\d+)\s*分钟后/#), let m = Int(match.1) {
            dueDate = now.addingTimeInterval(Double(m) * 60)
            explanations.append("「\(m)分钟后」→ \(Self.hm(dueDate!))")
        } else if let match = trimmed.firstMatch(of: #/(\d+)\s*个?小时后/#), let h = Int(match.1) {
            dueDate = now.addingTimeInterval(Double(h) * 3600)
            explanations.append("「\(h)小时后」→ \(Self.hm(dueDate!))")
        } else if trimmed.contains("半小时后") || trimmed.contains("半个小时后") {
            dueDate = now.addingTimeInterval(30 * 60)
            explanations.append("「半小时后」→ \(Self.hm(dueDate!))")
        } else {
            // ── 绝对时间：「(时段)X点(半)」，时段前缀决定上下午 ──
            var parsedHour: Int?
            var parsedMinute = 0
            if let match = trimmed.firstMatch(of: #/(\d{1,2})\s*点(半)?/#),
               var h = Int(match.1), (0...23).contains(h) {
                if match.2 != nil { parsedMinute = 30 }
                // 时段前缀：下午/傍晚/晚上/今晚 +12；中午=12；凌晨/早上/上午 原样
                let idx = trimmed.range(of: "\(h)")?.lowerBound ?? trimmed.startIndex
                let prefix = String(trimmed[..<idx])
                if h < 12, prefix.contains("下午") || prefix.contains("傍晚")
                    || prefix.contains("晚上") || prefix.contains("今晚") || prefix.contains("晚间") {
                    h += 12
                } else if prefix.contains("中午"), h < 11 {
                    h = 12
                }
                parsedHour = h
                explanations.append("解析时间 \(h):\(String(format: "%02d", parsedMinute))")
            }

            if trimmed.contains("明天") {
                let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
                dueDate = cal.date(bySettingHour: parsedHour ?? 18, minute: parsedMinute, second: 0, of: tomorrow)
                explanations.append("「明天」")
            } else if trimmed.contains("今晚") || trimmed.contains("今天") {
                dueDate = cal.date(bySettingHour: parsedHour ?? 18, minute: parsedMinute, second: 0, of: now)
            } else if let h = parsedHour {
                // 只有时间无日期：默认今天；真的已过才顺延到明天
                var candidate = cal.date(bySettingHour: h, minute: parsedMinute, second: 0, of: now)
                if let c = candidate, c < now {
                    candidate = cal.date(byAdding: .day, value: 1, to: c)
                    explanations.append("该时间已过，顺延到明天")
                }
                dueDate = candidate
            }
        }

        // ── 优先级标准（review：临近 ≠ 紧急，例行小事不因 deadline 提级）──
        // 高：仅明确紧急词；低：例行/周期类；其余默认中
        var priority: Priority = .medium
        let lower = trimmed.lowercased()
        let urgentWords = ["紧急", "立即", "马上", "尽快"]
        let routineWords = ["喝水", "打卡", "休息", "站起来", "眼睛", "伸展", "提醒我"]
        if urgentWords.contains(where: trimmed.contains) || lower.contains("asap") {
            priority = .high
            explanations.append("含紧急关键词 → 高")
        } else if routineWords.contains(where: trimmed.contains) {
            priority = .low
            explanations.append("例行提醒类 → 低")
        }

        // 周期任务：「每天/每日」→ 每天标签（完成后 AppStore 自动排下一次）
        var tags: [String] = []
        if trimmed.contains("每天") || trimmed.contains("每日") {
            tags = ["每天"]
            explanations.append("检测到周期任务「每天」")
        }

        return TodoDraft(
            title: trimmed.isEmpty ? "新任务" : trimmed,
            source: .manual,
            priority: priority,
            dueDate: dueDate,
            aiExplanation: explanations.isEmpty ? nil : explanations.joined(separator: "；"),
            tags: tags
        )
    }

    /// "HH:mm"
    nonisolated private static func hm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
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

    // MARK: 一句话建议（固定文案，真实现走 LLM）

    func generateDailySuggestion(_ ctx: ReportContext) async throws -> String {
        try? await Task.sleep(for: .seconds(0.3))
        return "建议: 上午先清超期项，会议间隙处理今日任务。"
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

// MARK: - AI 默认配置（hackathon：端点/模型固定，设置页只填 Key）

enum AIDefaults {
    /// 团队共用的 Azure Foundry 资源（OpenAI 兼容 /v1 端点）
    static let baseURL = "https://murphy-key-resource.services.ai.azure.com/openai/v1"
    /// 该资源唯一的部署：识图和文本生成都用它。
    /// 注意：换部署前先确认资源上真的部署了（目录可见 ≠ 已部署，没部署调用 404）
    static let model = "gpt-5.5"
    /// 推理力度：low 足够做「明天中午前」类日期换算（实测 ~3s），
    /// minimal 该模型不支持，medium 以上只会拖慢岛上等待动画
    static let reasoningEffort = "low"
}

// MARK: - OpenAI 兼容真实现（Azure AI Foundry /openai/v1 实测可用）

/// 任何 OpenAI 兼容端点都能用：baseURL 填到 /v1 为止。
/// Azure Foundry：https://<resource>.services.ai.azure.com/openai/v1，
/// model 必须是**部署名**（不是目录里的模型名），Bearer 鉴权实测通过。
@MainActor
final class OpenAIChatAIService: AIService {

    private let baseURL: String
    private let apiKey: String
    private let model: String

    /// - Parameters: 来自 settings.aiBaseURL / aiAPIKey / aiModel（AppDelegate 装配）
    init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: AIService

    func parseScreenshot(_ imageData: Data) async throws -> [TodoDraft] {
        let system = """
        你是任务提取助手。从用户的截图（聊天记录/会议纪要/邮件等）中提取待办事项。
        只输出 JSON 对象：{"todos": [{"title": "...", "priority": "high|medium|low", \
        "dueDate": "yyyy-MM-dd HH:mm" 或 null, "recurrence": "每天"/"每周一"等周期描述（非周期为 null）, \
        "aiExplanation": "一句话中文说明判断依据"}]}。
        当前时间：\(Self.now())。相对时间（明天/周五/下班前）换算成具体时间；\
        周期任务的 dueDate 给下一次发生时间（今天该时间已过则为明天/下个周期）；没有任务返回 {"todos": []}。
        """
        let content: [[String: Any]] = [
            ["type": "text", "text": "提取这张截图里的待办事项"],
            ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(imageData.base64EncodedString())"]],
        ]
        let reply = try await chat(system: system, userContent: content, jsonMode: true)
        return try Self.decodeDrafts(reply, source: .screenshot)
    }

    func parseQuickInput(_ text: String) async throws -> TodoDraft {
        let system = """
        你是任务解析助手。把用户的一句话解析成一个待办事项。
        只输出 JSON 对象：{"todos": [{"title": "...", "priority": "high|medium|low", \
        "dueDate": "yyyy-MM-dd HH:mm" 或 null, "recurrence": "每天"/"每周一"等周期描述（非周期为 null）, \
        "aiExplanation": "一句话中文说明判断依据"}]}。
        当前时间：\(Self.now())。title 保留原意但去掉时间词和周期词。\
        时间解析：支持相对时间（「15分钟后」「2小时后」= 当前时间 + 偏移）；\
        「晚上10点」=22:00、「下午3点」=15:00（时段前缀决定上下午）；\
        只有当解析出的时间确实早于当前时间才顺延到明天。\
        优先级标准（临近 ≠ 紧急）：仅文本含紧急语气（紧急/ASAP/立即/马上/尽快/不能拖）→ high；\
        喝水/打卡/休息等例行琐事 → low（即使截止临近也不提升）；其余有明确事项的 → medium。\
        周期任务（每天/每周X…）的 dueDate 给下一次发生时间（今天该时间已过则为明天/下个周期）。
        """
        let reply = try await chat(system: system, userContent: [["type": "text", "text": text]], jsonMode: true)
        guard let draft = try Self.decodeDrafts(reply, source: .manual).first else {
            throw AIServiceError.invalidResponse
        }
        return draft
    }

    func generateMorningReport(_ ctx: ReportContext) async throws -> String {
        try await report(
            ctx,
            instruction: """
            生成中文 markdown 晨报，以「# ☀️ 早安！」开头，结构依次为：
            一句话概览、## 🔥 优先处理（最多3条，加粗标题+截止说明）、## 📅 今日会议、\
            ## ✅ 个人 Todo、## 🧩 Jira、## 💡 建议（2-3条可执行建议）。语气轻快简洁。
            """
        )
    }

    func generateEveningReport(_ ctx: ReportContext) async throws -> String {
        try await report(
            ctx,
            instruction: """
            生成中文 markdown 晚报，以「# 🌙 晚上好，来复盘今天」开头，结构依次为：
            一句话完成度概览、## 🎉 今日完成（删除线列出）、## 🔥 优先处理（结转明天，最多3条）、\
            ## 📅 今日会议、## 🧩 Jira、## 💡 建议（含明早第一件事 + 休息提醒）。语气温和。
            """
        )
    }

    func generateDailySuggestion(_ ctx: ReportContext) async throws -> String {
        let reply = try await chat(
            system: """
            你是用户的个人工作助理。根据上下文给出一句话行动建议：30 字以内、\
            以「建议: 」开头、具体可执行（点名最该先做的事、如何利用会议间隙），不要换行。\
            只能引用上下文里明确列出的任务和会议，禁止臆造或引入列表之外的事项。
            """,
            userContent: [["type": "text", "text": Self.contextText(ctx)]],
            jsonMode: false
        )
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 内部

    private func report(_ ctx: ReportContext, instruction: String) async throws -> String {
        let reply = try await chat(
            system: "你是用户的个人工作助理。只输出 markdown 正文，不要代码块包裹。\(instruction)",
            userContent: [["type": "text", "text": Self.contextText(ctx)]],
            jsonMode: false
        )
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// chat completions 核心调用（jsonMode = response_format json_object）
    private func chat(system: String, userContent: [[String: Any]], jsonMode: Bool) async throws -> String {
        guard !apiKey.isEmpty, !baseURL.isEmpty, !model.isEmpty else {
            throw AIServiceError.notConfigured
        }
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw AIServiceError.notConfigured
        }

        var body: [String: Any] = [
            "model": model,
            "reasoning_effort": AIDefaults.reasoningEffort,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]
        if jsonMode { body["response_format"] = ["type": "json_object"] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            NSLog("[AI] HTTP \(code): \(String(data: data.prefix(300), encoding: .utf8) ?? "")")
            throw AIServiceError.invalidResponse
        }
        guard let content = try JSONDecoder().decode(ChatResponse.self, from: data)
            .choices.first?.message.content, !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }

    // MARK: 解析

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct DraftsEnvelope: Decodable { let todos: [DraftDTO] }
    private struct DraftDTO: Decodable {
        let title: String
        let priority: String?
        let dueDate: String?
        let recurrence: String?
        let aiExplanation: String?
    }

    nonisolated private static func decodeDrafts(_ reply: String, source: TodoSource) throws -> [TodoDraft] {
        // 防御：个别情况下模型仍会用 ```json 围栏包 JSON
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(DraftsEnvelope.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return envelope.todos.map { dto in
            TodoDraft(
                title: dto.title,
                source: source,
                priority: Priority(rawValue: dto.priority ?? "") ?? .medium,
                dueDate: dto.dueDate.flatMap(Self.parseDate),
                aiExplanation: dto.aiExplanation,
                tags: dto.recurrence.map { [$0] } ?? []
            )
        }
    }

    // MARK: 时间

    nonisolated private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f
    }()

    nonisolated private static func now() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        return f.string(from: Date())
    }

    nonisolated private static func parseDate(_ raw: String) -> Date? {
        dateTime.date(from: raw)
    }

    /// ReportContext → 纯文本上下文（喂给 LLM）
    nonisolated private static func contextText(_ ctx: ReportContext) -> String {
        var lines = ["当前时间：\(now())"]
        lines.append("\n未完成待办（\(ctx.pendingTodos.count)）：")
        for t in ctx.pendingTodos {
            let due = t.dueDate.map { dateTime.string(from: $0) } ?? "无截止"
            let src = t.source == .jira ? "Jira \(t.jiraKey ?? "")（\(t.jiraStatus ?? "To Do")）" : "个人"
            lines.append("- \(t.title) | \(t.priority.label) | \(due) | \(src)")
        }
        lines.append("\n今日已完成（\(ctx.completedToday.count)）：")
        for t in ctx.completedToday { lines.append("- \(t.title)") }
        lines.append("\n今日会议（\(ctx.meetings.count)）：")
        for m in ctx.meetings {
            let plat = m.platform.map { "（\($0.label)）" } ?? ""
            lines.append("- \(dateTime.string(from: m.start))–\(dateTime.string(from: m.end)) \(m.title)\(plat)")
        }
        return lines.joined(separator: "\n")
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

    func generateDailySuggestion(_ ctx: ReportContext) async throws -> String {
        guard !apiKey.isEmpty else { throw AIServiceError.notConfigured }
        throw AIServiceError.notImplemented
    }
}
