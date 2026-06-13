import Foundation
import SwiftUI

// ============================================================
// AppStore —— 单一数据源 + 状态机入口。
// 所有 UI 读这里，所有变更走这里的方法（todo-data spec）。
// ============================================================

@MainActor
final class AppStore: ObservableObject {

    // MARK: - 数据

    @Published private(set) var todos: [Todo] = [] { didSet { persistTodos() } }
    @Published private(set) var meetings: [Meeting] = [] { didSet { Persistence.save(meetings, to: "meetings.json") } }
    /// 邮件提炼的一句话提醒消息（message-inbox spec），持久化 messages.json
    @Published private(set) var messages: [Message] = [] { didSet { Persistence.save(messages, to: "messages.json") } }
    /// 各渠道@我的条目（只读，不落盘——每次同步重新拉取）
    @Published private(set) var mentions: [Mention] = []
    /// 已读标记：id → 标记当时的 updated 时间。落盘，重启保留。
    /// 之后该条若有更新的活动（updated 更新）会重新视为未读冒出来
    @Published private(set) var mentionReads: [String: Date] = [:] {
        didSet { Persistence.save(mentionReads, to: "mentionReads.json") }
    }

    /// 未读提及：从未读过，或上次读后又有新活动
    var unreadMentions: [Mention] {
        mentions.filter { m in
            guard let readAt = mentionReads[m.id] else { return true }
            guard let updated = m.updated else { return false } // 无时间且已读 → 隐藏
            return updated > readAt
        }
    }

    func replaceMentions(_ new: [Mention]) {
        mentions = new
        // 防止 mentionReads 无限增长：只保留仍在结果里的条目
        let liveIDs = Set(new.map(\.id))
        mentionReads = mentionReads.filter { liveIDs.contains($0.key) }
    }

    /// 标记某条已读（点开跳转时调用）→ 从未读列表消失
    func markMentionRead(_ mention: Mention) {
        mentionReads[mention.id] = mention.updated ?? Date()
    }
    @Published var settings = AppSettings() { didSet { Persistence.save(settings, to: "settings.json") } }

    // MARK: - Island 状态

    @Published private(set) var islandState: IslandState = .normal
    /// AI 是否工作中（驱动 aiWorking 态 + 流光）
    @Published var isAIWorking = false { didSet { refreshCompactState() } }
    /// 今日全部完成后 compact 显示皇冠
    @Published private(set) var crownedToday = false
    /// 加冕日期：跨天自动失效（review-fixes #13）
    private var crownedDate: Date?

    private func expireCrownIfStale() {
        if crownedToday, let d = crownedDate, !Calendar.current.isDateInToday(d) {
            crownedToday = false
        }
    }

    /// 状态变化的副作用回调（动效/庆祝窗口挂这里，由 AppDelegate 装配）
    var onCompletedAll: (() -> Void)?
    var onTodoCompleted: ((Todo) -> Void)?
    var onTodoLanded: ((Todo) -> Void)?
    /// 手动刷新的实际同步逻辑（Jira/日历），AppDelegate 装配
    var onRefresh: (() async -> Void)?
    /// 从剪贴板贴图识别（兼容外部截图工具），AppDelegate 装配
    var onPasteScreenshot: (() -> Void)?

    /// 触发剪贴板贴图识别（面板按钮/菜单调用）
    func pasteScreenshot() { onPasteScreenshot?() }

    /// tab 顺序（用户可拖动）：按 settings.tabOrder 排，新增/缺失的 tab 补到末尾
    static let defaultTabs: [PanelTab] = [.today, .calendar, .messages, .inbox, .agent]
    var orderedVisibleTabs: [PanelTab] {
        let saved = settings.tabOrder.compactMap(PanelTab.init(rawValue:)).filter(Self.defaultTabs.contains)
        let rest = Self.defaultTabs.filter { !saved.contains($0) }
        return saved + rest
    }

    /// 拖动重排：把 tab 移到 target 之前/后，持久化
    func moveTab(_ tab: PanelTab, before target: PanelTab) {
        guard tab != target else { return }
        var arr = orderedVisibleTabs
        guard let from = arr.firstIndex(of: tab) else { return }
        arr.remove(at: from)
        let insertAt = arr.firstIndex(of: target) ?? arr.count
        arr.insert(tab, at: insertAt)
        settings.tabOrder = arr.map(\.rawValue)
    }

    /// 快速录入里 ⌘V 贴图后回车：直接拿 PNG 走截图 AI 流水线（AppDelegate 装配）
    var onRecognizeImage: ((Data) -> Void)?

    /// 识别已贴入快速录入框的截图
    func recognizeImage(_ data: Data) { onRecognizeImage?(data) }

    /// ⌥Space 语音速记：QuickInputCard onAppear 读到 true 即自动开始聆听，用后自清
    @Published var quickInputAutoVoice = false

    /// 从展开面板里点 + 进 quickInput 时记住来源 tab：完成/取消后回到面板继续操作，
    /// 而不是一路收起到刘海再让用户重新挪回去。nil = 来源是 compact（全局 ⌥Space 等），回落 compact。
    private var quickInputOrigin: PanelTab?

    private var currentExpandedTab: PanelTab? {
        if case .expanded(let tab) = islandState { return tab }
        return nil
    }

    /// 点 + 弹快速录入：记住来源面板（手动新建不自动语音）。
    /// 注意先取来源再 present——present 会把 islandState 切成 .quickInput 并清空 origin。
    func presentQuickInput() {
        let origin = currentExpandedTab
        quickInputAutoVoice = false
        present(.quickInput)
        quickInputOrigin = origin
    }

    /// quickInput 完成/取消：有来源面板就回到面板继续操作，否则回落 compact
    func closeQuickInput() {
        guard let tab = quickInputOrigin else { dismiss(); return }
        quickInputNotice = nil
        cardHeld = false
        present(.expanded(tab: tab))   // present 内部已清空 quickInputOrigin
    }

    /// 弹出快速录入并自动开始语音（全局热键/菜单调用）
    func presentVoiceInput() {
        let origin = currentExpandedTab
        quickInputAutoVoice = true
        present(.quickInput)
        quickInputOrigin = origin
    }
    /// 提醒事项任务完成/撤销 → EventKit 回写（calendarItemIdentifier, 完成态），AppDelegate 装配
    var onReminderCompletionChanged: ((String, Bool) -> Void)?
    /// 提醒事项 snooze → 把新截止时间回写 EventKit（calendarItemIdentifier, 新时间），AppDelegate 装配
    var onReminderSnoozed: ((String, Date) -> Void)?
    /// 删除苹果来源项 → 从 EventKit 真删除对应事件/提醒（eventIdentifier），AppDelegate 装配
    var onCalendarItemDeleted: ((String) -> Void)?
    /// agent 一轮完成（转入 replied）→ 提示音 + 完成通知卡，AppDelegate 装配（声音/前台判断属 AppKit）
    var onAgentReplied: ((AgentSession) -> Void)?

    // MARK: - Agent 会话（agent-session spec，借鉴 Vibe Island）
    // 独立于 todo：coding agent 的瞬态监控，只驱动收缩态徽章，不进任何列表。

    @Published private(set) var agentSessions: [AgentSession] = []

    /// 运行中（左翼 active 计数）
    var activeAgentCount: Int { agentSessions.filter { $0.state == .working }.count }
    /// 需要你处理：已回复 + 等待确认（右翼计数）
    var waitingAgentCount: Int { agentSessions.filter { $0.state.needsAttention && isUnseenAgent($0) }.count }
    /// 有任意徽章 → 收缩态加宽
    var hasAgentBadge: Bool { activeAgentCount > 0 || waitingAgentCount > 0 }

    /// 应用一条 hook 事件（AgentSessionService 解析 JSONL 后调用）
    func applyAgentEvent(_ event: AgentEvent) {
        guard let mapped = event.mappedState else { return }
        if mapped == .ended {
            agentSessions.removeAll { $0.id == event.session_id }
            return
        }
        var becameReplied = false
        var replied: AgentSession?
        if let i = agentSessions.firstIndex(where: { $0.id == event.session_id }) {
            // 转入 replied 的瞬间（之前不是 replied）= agent 这一轮刚完成
            becameReplied = mapped == .replied && agentSessions[i].state != .replied
            agentSessions[i].state = mapped
            agentSessions[i].updatedAt = Date()
            if mapped == .waiting { agentSessions[i].message = event.message }
            if let cwd = event.cwd, !cwd.isEmpty { agentSessions[i].cwd = cwd }
            if let term = event.terminal { agentSessions[i].terminal = term }
            // 非空才覆盖，保留已有值（Stop 不带 prompt、UserPromptSubmit 不带 name/answer）
            if let t = event.title, !t.isEmpty { agentSessions[i].title = t }
            if let n = event.name, !n.isEmpty { agentSessions[i].name = n }
            if let a = event.answer, !a.isEmpty { agentSessions[i].answer = a }
            replied = agentSessions[i]
        } else {
            becameReplied = mapped == .replied  // 首个事件就是完成（少见但也算一次完成）
            let s = AgentSession(
                id: event.session_id,
                agent: event.agent ?? "Claude Code",
                cwd: event.cwd,
                state: mapped,
                message: event.message,
                updatedAt: Date(),
                terminal: event.terminal,
                title: event.title?.isEmpty == false ? event.title : nil,
                name: event.name?.isEmpty == false ? event.name : nil,
                answer: event.answer?.isEmpty == false ? event.answer : nil
            )
            agentSessions.append(s)
            replied = s
        }
        if becameReplied, let replied { onAgentReplied?(replied) }
    }

    /// 陈旧清理：运行中的会话视为"开着"不清理（Agent tab 要展示所有打开的 session）；
    /// 已完成/待确认的长时间(6h)无更新才清（兜底，正常靠 SessionEnd 移除）
    func sweepStaleAgentSessions(now: Date = Date()) {
        agentSessions.removeAll { s in
            guard s.state != .working else { return false } // 运行中 = 开着，永不清
            return now.timeIntervalSince(s.updatedAt) > 6 * 3600
        }
    }

    /// Debug/测试：直接塞一个会话
    func debugUpsertAgentSession(id: String, state: AgentSessionState, project: String, message: String? = nil) {
        applyAgentEvent(AgentEvent(
            event: state == .waiting ? "Notification" : (state == .replied ? "Stop" : "UserPromptSubmit"),
            session_id: id, cwd: "/Users/me/\(project)", message: message, agent: "Claude Code"
        ))
    }

    func clearAgentSessions() { agentSessions.removeAll() }

    /// 标记某 agent 会话已处理 → 从列表移除（Today/Agent 栏点「已完成」圈）。
    /// 该 session 之后若再来新事件（如又发了 prompt）会按新事件重新出现。
    func acknowledgeAgentSession(_ id: String) {
        agentSessions.removeAll { $0.id == id }
    }

    /// 跳转到 agent 所属终端 session（Agent 面板/卡片点击），AppDelegate 装配 → AgentSessionService.jumpTo
    var onAgentJump: ((AgentSession) -> Void)?

    /// 已查看（点过跳转）的会话 → 记录当时 updatedAt。Today 栏与铃铛据此隐藏；
    /// 该会话之后再有新活动（updatedAt 变新）会重新冒出来。Agent tab 仍展示全部。
    private var seenAgentAt: [String: Date] = [:]

    private func isUnseenAgent(_ s: AgentSession) -> Bool {
        guard let seen = seenAgentAt[s.id] else { return true }
        return s.updatedAt > seen
    }

    func jumpToAgent(_ session: AgentSession) {
        seenAgentAt[session.id] = session.updatedAt   // 点过即视为已查看
        onAgentJump?(session)
        // 先激活目标 app，再收起面板——否则展开的灵动岛盖住目标，像「没反应」
        dismiss()
    }

    /// Agent 面板（tab）：全部会话，需处理的在前、运行中在后，各按最近更新排
    var sortedAgentSessions: [AgentSession] {
        agentSessions.sorted { a, b in
            if a.state.needsAttention != b.state.needsAttention { return a.state.needsAttention }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Today 的 Agent 栏：需处理（已完成/待确认）且未点击过的，运行中/已查看的不露出
    var attentionAgentSessions: [AgentSession] {
        sortedAgentSessions.filter { $0.state.needsAttention && isUnseenAgent($0) }
    }

    // MARK: - 日历权限（未授权时日历面板空态引导授权）

    /// 日历权限 UI 状态（AppDelegate 按 EKAuthorizationStatus 维护）
    enum CalendarAuthUIState: Equatable, Sendable {
        case authorized    // 日历/提醒至少一项可读
        case needsRequest  // 未决定 → 可直接弹系统授权弹窗
        case denied        // 被拒/受限 → 系统不允许再弹，只能去系统设置开启
    }
    /// 默认 authorized：AppDelegate 写入真实状态前，空态不闪授权引导
    @Published var calendarAuthState: CalendarAuthUIState = .authorized
    /// 「允许访问日历 / 前往系统设置」按钮动作，AppDelegate 装配
    var onRequestCalendarAccess: (() -> Void)?

    func requestCalendarAccess() { onRequestCalendarAccess?() }

    /// 刷新进行中（刷新按钮转圈用）
    @Published private(set) var isRefreshing = false

    /// 任意 NSMenu 跟踪中（Debug 菜单/右键菜单/卡内 Menu）——
    /// 悬停收起与卡片倒计时让路（review-fixes #12，AppDelegate 观察系统通知维护）
    @Published var isMenuTracking = false
    /// 用户已开始编辑当前卡片（聚焦输入/点击）→ 解除自动收回（review-fixes #8）
    @Published var cardHeld = false

    /// 快速录入卡顶部的提示条（截图解析失败/未识别时由 AppDelegate 注入，dismiss 清除）
    @Published var quickInputNotice: String?

    /// Today 面板底部的 AI 一句话建议（AppDelegate 调 AIService 生成后注入；
    /// 默认值即未配置 Key / 生成失败时的兜底文案）
    @Published private(set) var aiSuggestion = "建议: 上午先清超期项，会议间隙处理今日任务。"

    func updateAISuggestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        aiSuggestion = trimmed
    }

    /// 手动刷新：立即同步外部数据源，不等轮询周期
    func refresh() {
        guard !isRefreshing, let onRefresh else { return }
        isRefreshing = true
        Task { @MainActor [weak self] in
            await onRefresh()
            self?.isRefreshing = false
        }
    }

    // MARK: - 磁盘清理（disk-cleanup spec）
    // 借鉴 storage-analyzer skill：只读 du 扫描 → 大模型分安全档 → 移废纸篓。
    // 结果不落盘（每次打开重新扫，避免路径过期）；服务由 AppDelegate 按 AI 配置装配。

    enum DiskScanStatus: Equatable {
        case idle, scanning, classifying, done
        case failed(String)
    }

    @Published private(set) var diskScanStatus: DiskScanStatus = .idle
    @Published private(set) var diskCapacity: DiskCapacity?
    @Published private(set) var diskClassified: [ClassifiedEntry] = []
    @Published private(set) var diskReclaimedBytes: Int64 = 0
    @Published private(set) var diskInaccessiblePaths: [String] = []
    /// true = 分类回退到规则（无 AI Key / AI 失败），UI 提示
    @Published private(set) var diskAIUnavailable = false
    /// 移废纸篓单项失败的就地反馈（成功清除）
    @Published private(set) var diskActionError: String?

    /// 磁盘清理服务提供者（AppDelegate 装配，按 AI 配置选实现）。服务无状态，按需新建。
    var diskCleanupServiceProvider: (() -> DiskCleanupService)?

    var diskReclaimedHuman: String {
        ByteCountFormatter.string(fromByteCount: diskReclaimedBytes, countStyle: .file)
    }

    /// 触发一次扫描 → 分类。重复触发在进行中时忽略。
    func runDiskScan() {
        guard let provider = diskCleanupServiceProvider else { return }
        guard diskScanStatus != .scanning, diskScanStatus != .classifying else { return }
        let service = provider()
        diskScanStatus = .scanning
        diskActionError = nil
        diskReclaimedBytes = 0
        diskAIUnavailable = false
        diskClassified = []
        Task { @MainActor in
            do {
                let result = try await service.scan()
                diskCapacity = result.capacity
                diskInaccessiblePaths = result.inaccessiblePaths
                diskScanStatus = .classifying
                let classification = await service.classify(result.entries)
                diskClassified = classification.entries.sorted { $0.entry.sizeBytes > $1.entry.sizeBytes }
                diskAIUnavailable = classification.aiUnavailable
                diskScanStatus = .done
            } catch {
                diskScanStatus = .failed(error.localizedDescription)
            }
        }
    }

    /// 移到废纸篓（可恢复）。成功 → 从列表移除、累加已释放、更新可用容量。
    func trashDiskEntry(_ classified: ClassifiedEntry) {
        guard let provider = diskCleanupServiceProvider else { return }
        diskActionError = nil
        do {
            try provider().trash(classified.entry)
            diskClassified.removeAll { $0.id == classified.id }
            diskReclaimedBytes += classified.entry.sizeBytes
            if let cap = diskCapacity {
                diskCapacity = DiskCapacity(total: cap.total, free: cap.free + classified.entry.sizeBytes)
            }
        } catch {
            diskActionError = "「\(classified.entry.name)」移到废纸篓失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 动效触发器（UI 绑定，effects 模块消费）

    /// 新任务降落 → Touchdown 涟漪颜色来源（TouchdownModifier 播完自动清回 nil）
    @Published var landedSource: TodoSource?
    /// 完成计数器：递增一次 = 播一次金色高光 + 撒花
    @Published private(set) var completionFlash = 0

    private var completedFlashTask: Task<Void, Never>?

    init() {
        // 首次启动从空开始，不种演示数据；演示数据只通过
        // Debug 菜单「重置演示数据」显式载入（Demo 兜底）
        todos = Persistence.load([Todo].self, from: "todos.json") ?? []
        meetings = Persistence.load([Meeting].self, from: "meetings.json") ?? []
        // 清洗历史落盘消息：① 去掉演示邮件（Mock 固定数据）② 去掉 Jira/Confluence 通知
        // （已在 Mentions 页签呈现，不重复）③ 去掉非真人自动通知（产品更新/营销/系统告警/邀请等，
        // 按展示名+原主题兜底判定）④ 抹掉打不开的 message:// 链接（点了只会弹 Mail 1030 错误）
        messages = (Persistence.load([Message].self, from: "messages.json") ?? [])
            .filter { msg in
                !Self.isDemoMessageId(msg.messageId)
                    && msg.source != .jira
                    && !EmailPreprocess.isAutomatedSenderName(msg.sender ?? "", subject: msg.rawSubject ?? "")
            }
            .map { msg in
                guard msg.link?.scheme == "message" else { return msg }
                var m = msg; m.link = nil; return m
            }
        if let saved = Persistence.load(AppSettings.self, from: "settings.json") {
            settings = saved
        }
        mentionReads = Persistence.load([String: Date].self, from: "mentionReads.json") ?? [:]
        refreshCompactState()
    }

    // MARK: - 状态机操作

    /// 切换到事件态（卡片/展开/晨晚报）
    func present(_ state: IslandState) {
        cardHeld = false
        quickInputOrigin = nil   // 默认清空；presentQuickInput/Voice 会在 present 之后重设
        withAnimation(IslandAnimation.spring) { islandState = state }
    }

    /// 回落到自动派生的 compact 态
    func dismiss() {
        cardHeld = false
        quickInputNotice = nil
        expireCrownIfStale()
        withAnimation(IslandAnimation.spring) { islandState = derivedCompactState() }
    }

    /// 数据变化后刷新 compact 态（仅当前处于 compact 时生效，不打断卡片/展开态）
    func refreshCompactState() {
        expireCrownIfStale()
        guard islandState.isCompact else { return }
        let derived = derivedCompactState()
        if derived != islandState {
            withAnimation(IslandAnimation.spring) { islandState = derived }
        }
    }

    private func derivedCompactState() -> IslandState {
        if isAIWorking { return .aiWorking }
        if crownedToday && pendingTodos.allSatisfy({ $0.source == .jira }) { return .celebrate }
        // compact 以「今日可动手的事」为准：个人的事做完 → 打钩清空态。
        // 明天的任务、只读的 Jira/GitHub ticket 都不在刘海上挂数字
        guard todayActionableCount > 0 else { return .idle }

        // 逐任务按各自 AI 提前量判定高亮：会议（提前量大）更早进入 near/urgent，
        // 吃饭喝水（提前量小）只在临近才亮 —— 不再全局一刀切 60/15min
        let endOfToday = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        var level = 0 // 0 normal · 1 near · 2 urgent
        for todo in pendingTodos where !Self.readOnlySources.contains(todo.source) {
            if let snooze = todo.snoozedUntil, snooze > Date() { continue }
            guard let anchor = todo.snoozedUntil ?? todo.dueDate, anchor < endOfToday else { continue }
            let interval = anchor.timeIntervalSinceNow
            if interval < 0 || interval < Double(todo.finalWindowMinutes * 60) {
                level = max(level, 2)
            } else if interval < Double(todo.effectiveLeadMinutes * 60) {
                level = max(level, 1)
            }
        }
        switch level {
        case 2: return .urgent
        case 1: return .near
        default: return .normal
        }
    }

    // MARK: - 派生数据

    var pendingTodos: [Todo] { todos.filter { !$0.isCompleted } }

    var pendingCount: Int { pendingTodos.count }

    /// 最近一个截止时间（未完成，未被 snooze 压住）
    var nextDue: Date? {
        pendingTodos.compactMap { todo -> Date? in
            // 与 overdueTodos 口径一致：非活跃 Jira 的陈年 duedate 不驱动紧急色
            // （否则 compact 红色 urgent 而面板里无任何超期项，review-fixes #10）
            if todo.source == .jira, !isActiveJira(todo) { return nil }
            if let snooze = todo.snoozedUntil, snooze > Date() { return nil }
            return todo.dueDate
        }.min()
    }

    /// 今日范围内（含已过期）最近截止 —— compact 态派生与右翼倒计时用，
    /// 不含明天及以后（明早的任务不该让刘海显示成"有事待办"）
    var todayNextDue: Date? {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        return pendingTodos.compactMap { todo -> Date? in
            if let snooze = todo.snoozedUntil, snooze > Date() { return nil }
            guard let due = todo.dueDate, due < endOfToday else { return nil }
            return due
        }.min()
    }

    /// 紧急度 × 临近度 综合排序（todo-data spec）
    private func sorted(_ list: [Todo]) -> [Todo] {
        list.sorted {
            if $0.priority.sortRank != $1.priority.sortRank {
                return $0.priority.sortRank < $1.priority.sortRank
            }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    /// 三大分组（Inbox / 旧视图仍在用）
    var personalTodos: [Todo] { sorted(pendingTodos.filter { $0.source != .jira }) }
    var jiraTodos: [Todo] { sorted(pendingTodos.filter { $0.source == .jira }) }
    var todayMeetings: [Meeting] {
        meetings
            .filter { Calendar.current.isDateInToday($0.start) }
            .sorted { $0.start < $1.start }
    }

    /// 按日期分组的会议列表（CalendarPanel 多日视图消费）
    /// 每组包含日期（startOfDay）和该日所有会议（按 start 升序），按日期升序排列
    var meetingsByDate: [(date: Date, meetings: [Meeting])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: meetings) { cal.startOfDay(for: $0.start) }
        return grouped
            .map { (date: $0.key, meetings: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - 今日焦点派生（today-focus-redesign spec）
    // Today 只回答「我今天要关注什么」：按时间相关性筛选，来源只是行内标识。

    /// Jira 活跃状态兜底名单（仅 jiraStatusCategory 缺失的旧数据走这里）。
    /// status.name 随站点语言本地化（中文站是「待办」），不能作为主判断。
    private static let jiraInactiveStatuses: Set<String> = [
        "to do", "todo", "open", "backlog", "done", "cancelled", "canceled", "closed",
    ]

    /// Jira 活跃 = statusCategory 为 In Progress 类（用户正在做的才算今天的事）。
    /// statusCategory.key 是机器值（new / indeterminate / done），不随站点语言变化。
    private func isActiveJira(_ todo: Todo) -> Bool {
        guard todo.source == .jira else { return false }
        if let category = todo.jiraStatusCategory {
            return category == "indeterminate"
        }
        let status = (todo.jiraStatus ?? "").lowercased()
        return !Self.jiraInactiveStatuses.contains(status)
    }

    /// 已超期：个人来源全部计入；Jira 仅活跃状态计入（陈年 To Do 的过期 duedate 是噪音）
    var overdueTodos: [Todo] {
        sorted(pendingTodos.filter { $0.isOverdue && ($0.source != .jira || isActiveJira($0)) })
    }

    /// 外部只读来源（Jira/GitHub）——不可点击完成，今日任务里沉底展示
    private func isExternal(_ todo: Todo) -> Bool {
        todo.source == .jira || todo.source == .github
    }

    /// 今日任务·有时间：可完成的个人任务，今天截止未超期（含 Snooze 今天到点），按时间排。
    /// 外部只读项不在此列——可点击完成的排最上（today-focus 布局约定）
    var todayTimedTodos: [Todo] {
        pendingTodos
            .filter { todo in
                guard !isExternal(todo), !todo.isOverdue else { return false }
                let anchor = todo.snoozedUntil ?? todo.dueDate
                guard let anchor else { return false }
                return Calendar.current.isDateInToday(anchor)
            }
            .sorted { ($0.snoozedUntil ?? $0.dueDate!) < ($1.snoozedUntil ?? $1.dueDate!) }
    }

    /// 今日任务·无固定时间：无截止的个人任务，按优先级排
    var todayUntimedTodos: [Todo] {
        let overdueIDs = Set(overdueTodos.map(\.id))
        return sorted(pendingTodos.filter { todo in
            guard !isExternal(todo), !overdueIDs.contains(todo.id) else { return false }
            return todo.dueDate == nil
        })
    }

    /// 今日任务·外部只读（沉底）：活跃 Jira + GitHub PR（待 review/已指派即「当下要处理」）
    var todayExternalTodos: [Todo] {
        let overdueIDs = Set(overdueTodos.map(\.id))
        return sorted(pendingTodos.filter { todo in
            guard !overdueIDs.contains(todo.id) else { return false }
            if todo.source == .jira { return isActiveJira(todo) }
            return todo.source == .github
        })
    }

    /// Inbox（Later 页签）：仅外部来源待办（To Do 状态 Jira / 未进焦点的 GitHub）。
    /// later-into-calendar：个人任务不再进 Later，统一收敛到 Calendar 页签时间线。
    var inboxTodos: [Todo] {
        let focusIDs = Set((overdueTodos + todayTimedTodos + todayUntimedTodos + todayExternalTodos).map(\.id))
        return sorted(pendingTodos.filter { !focusIDs.contains($0.id) && isExternal($0) })
    }

    /// Calendar 页签承载的本地个人任务（later-into-calendar）：本地创建（含已完成）。
    /// 排除外部来源（Jira/GitHub）与 `.calendar` 来源——后者已作为 Meeting 展示，避免重复。
    /// 已完成的保留展示（删除线、不隐藏）；有截止按 dueDate 归入对应日期，无截止落「无固定时间」。
    var calendarPersonalTodos: [Todo] {
        sorted(todos.filter { !isExternal($0) && $0.source != .calendar })
    }

    /// 今日焦点数（Today 面板问候语用，与面板列表一致，含只读 ticket）
    var todayFocusCount: Int {
        overdueTodos.count + todayTimedTodos.count + todayUntimedTodos.count + todayExternalTodos.count
    }

    /// 只读外部源：app 内不可完成，不应阻塞刘海打钩/庆祝
    private static let readOnlySources: Set<TodoSource> = [.jira, .github]

    /// 今日「可动手」数（compact 计数与打钩判定用）：排除只读 ticket——
    /// In Progress 的 Jira 会挂很多天，个人的事做完了刘海就该打钩
    var todayActionableCount: Int {
        (overdueTodos + todayTimedTodos + todayUntimedTodos)
            .filter { !Self.readOnlySources.contains($0.source) }
            .count
    }
    var completedToday: [Todo] {
        todos.filter {
            guard let done = $0.completedAt else { return false }
            return Calendar.current.isDateInToday(done)
        }
    }

    var reportContext: ReportContext {
        ReportContext(pendingTodos: pendingTodos, completedToday: completedToday, meetings: todayMeetings)
    }

    // MARK: - Todo CRUD

    func add(_ todo: Todo) {
        todos.append(todo)
        onTodoLanded?(todo)
        if settings.effectsEnabled {
            landedSource = todo.source
        }
        refreshCompactState()
    }

    func add(drafts: [TodoDraft]) {
        for draft in drafts where draft.isSelected {
            todos.append(draft.toTodo())
        }
        refreshCompactState()
    }

    func update(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i] = todo
        refreshCompactState()
    }

    func delete(_ todo: Todo) {
        // 苹果来源项：从 EventKit 真删除对应事件/提醒，并清掉本地镜像（meetings）
        if todo.source == .calendar, let key = todo.calendarEventId {
            onCalendarItemDeleted?(key)
            meetings.removeAll { $0.eventIdentifier == key }
        }
        todos.removeAll { $0.id == todo.id }
        refreshCompactState()
    }

    /// 删除日历时间线里的 Meeting 行（later-into-calendar）：
    /// 有 eventIdentifier（真实苹果项）→ EventKit 真删除 + 清本地镜像；演示数据仅本地移除。
    func deleteMeeting(_ meeting: Meeting) {
        if let key = meeting.eventIdentifier {
            onCalendarItemDeleted?(key)
            meetings.removeAll { $0.eventIdentifier == key }
            todos.removeAll { $0.source == .calendar && $0.calendarEventId == key }
        } else {
            meetings.removeAll { $0.id == meeting.id }
        }
        refreshCompactState()
    }

    /// 完成(✓)可用性（later-into-calendar / calendar-complete-untimed）：
    /// ① 苹果来源 `.calendar` 项均可完成（事件本地完成 / 提醒回写）——这些 todo 仅当天项生成；
    /// ② 本地自定义任务：截止今天、已超期或无固定时间（无截止）均可完成。
    /// 仅未来截止的本地任务、Jira/GitHub 不可完成。
    func canComplete(_ todo: Todo) -> Bool {
        if isExternal(todo) { return false }
        if todo.source == .calendar { return true }
        // 无固定时间（无截止）的本地任务也可完成；仅未来截止不可完成（显示小点）
        guard let anchor = todo.effectiveDue else { return true }
        return todo.isOverdue || Calendar.current.isDateInToday(anchor)
    }

    /// 日历页签里 Meeting 行的完成可用性：今天（及更早）的苹果项可完成，未来项显示小点不可完成。
    func isMeetingCompletable(_ meeting: Meeting) -> Bool {
        let cal = Calendar.current
        return cal.startOfDay(for: meeting.start) <= cal.startOfDay(for: Date())
    }

    /// 切换苹果来源会议的完成态：定位其当日 `.calendar` todo 复用 complete/uncomplete
    /// （事件本地完成；提醒经 complete 内的回写同步苹果）。
    func toggleMeetingCompleted(_ meeting: Meeting) {
        guard let key = meeting.eventIdentifier,
              let todo = todos.first(where: { $0.source == .calendar && $0.calendarEventId == key })
        else { return }
        if todo.isCompleted { uncomplete(todo) } else { complete(todo) }
    }

    /// 删除可用性：本地任务 + 苹果来源（事件/提醒）可删；Jira/GitHub 只读不可删。
    func canDelete(_ todo: Todo) -> Bool { !isExternal(todo) }

    func complete(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].completedAt = Date()
        completionFlash += 1
        onTodoCompleted?(todos[i])

        // 提醒事项来源：回写 EventKit isCompleted（日历事件无完成语义，不回写）
        if let key = reminderEventId(of: todos[i]) {
            onReminderCompletionChanged?(key, true)
        }

        // 周期任务（每天/每周X）：完成本次后自动排下一次
        // （在庆祝判断之前 append，周期任务不算"清零"）
        if let next = Self.nextOccurrence(of: todos[i]) {
            todos.append(next)
        }

        // Jira 是只读集成不可完成，庆祝以「个人 Todo 清零」为准
        if pendingTodos.allSatisfy({ $0.source == .jira }) {
            // 完成今日全部 → 全屏庆祝 + 皇冠（effects spec）
            crownedToday = true
            crownedDate = Date()
            onCompletedAll?()
            present(.celebrate)
        } else if islandState.isCompact {
            // justCompleted 是 compact 闪光态——只在收缩态播；
            // 在展开面板里点完成时保持面板不塌，金色高光(completionFlash)照常播
            flashJustCompleted()
        } else if case .reminder(let shown) = islandState, shown.id == todo.id {
            // 提醒卡上的任务被标记完成：卡片使命结束，收卡回落
            // （否则卡片留在原地，用户感觉「点了没反应」）
            dismiss()
        }
    }

    func uncomplete(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        let completedAt = todos[i].completedAt
        todos[i].completedAt = nil
        crownedToday = false

        // 提醒事项撤销完成：回写取消，否则下一轮合并会按 EventKit 完成态把它翻回已完成
        if let key = reminderEventId(of: todos[i]) {
            onReminderCompletionChanged?(key, false)
        }

        // 周期任务撤销完成：回收完成时自动生成的下一次，避免重复
        if !todo.tags.filter({ $0.hasPrefix("每") }).isEmpty, let completedAt {
            if let spawned = todos.firstIndex(where: {
                $0.id != todo.id && !$0.isCompleted
                    && $0.title == todo.title && $0.tags == todo.tags
                    && $0.createdAt >= completedAt
            }) {
                todos.remove(at: spawned)
            }
        }
        refreshCompactState()
    }

    /// 周期任务的下一次发生：dueDate 顺延（每天+1 / 每周X+7），
    /// 跳过仍然过期的占位；无固定时间的周期任务暂不自动续（避免完成后立刻重现）
    private static func nextOccurrence(of todo: Todo) -> Todo? {
        guard todo.tags.contains(where: { $0.hasPrefix("每") }),
              let due = todo.dueDate else { return nil }
        let days = todo.tags.contains(where: { $0.hasPrefix("每周") }) ? 7 : 1
        let cal = Calendar.current

        var nextDue = cal.date(byAdding: .day, value: days, to: due) ?? due
        while nextDue < Date(), let bumped = cal.date(byAdding: .day, value: days, to: nextDue) {
            nextDue = bumped
        }

        var next = todo
        next.id = UUID()
        next.dueDate = nextDue
        next.createdAt = Date()
        next.completedAt = nil
        next.snoozedUntil = nil
        next.snoozeCount = 0
        return next
    }

    func snooze(_ todo: Todo, until date: Date) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].snoozedUntil = date
        todos[i].snoozeCount += 1
        // 来源是 Apple 提醒事项 → 把新时间回写 EventKit，提醒事项 App 也同步
        if let rid = reminderEventId(of: todos[i]) {
            onReminderSnoozed?(rid, date)
        }
        dismiss()
    }

    /// 完成单个后的 1s 金色闪光，随后回落
    private func flashJustCompleted() {
        completedFlashTask?.cancel()
        withAnimation(IslandAnimation.spring) { islandState = .justCompleted }
        completedFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            // 闪光窗口内用户可能已展开面板 / 被 jiraLanded 抢占——仍是闪光态才回落
            guard !Task.isCancelled, self?.islandState == .justCompleted else { return }
            self?.dismiss()
        }
    }

    // MARK: - Meeting 同步（CalendarService 调用）

    func replaceMeetings(_ new: [Meeting]) {
        meetings = new
        mergeCalendarTodos()
        refreshCompactState()
    }

    /// 当天日程/提醒 → `.calendar` 任务合并（today-tasks-schedule-reminders spec）。
    /// 按 calendarEventId upsert：标题/时间以日历为准，本地完成/snooze 状态保留（不复活）；
    /// 本次同步未出现且未完成的项 prune（事件被删 / 跨天残留 / 权限回收清空）。
    private func mergeCalendarTodos() {
        // 今日且携带稳定标识的项才入任务；演示数据无标识不参与。
        // 重复事件同日多实例共享 eventIdentifier → 取首个（按 start 升序）
        var seen = Set<String>()
        var fetched: [(meeting: Meeting, key: String)] = []
        for meeting in todayMeetings {
            guard let key = meeting.eventIdentifier, !seen.contains(key) else { continue }
            seen.insert(key)
            fetched.append((meeting, key))
        }

        todos.removeAll { todo in
            guard todo.source == .calendar, !todo.isCompleted,
                  let key = todo.calendarEventId else { return false }
            return !seen.contains(key)
        }

        for (meeting, key) in fetched {
            // 全天事件/无时间提醒不给 dueDate：落「无固定时间」分区，不触发提醒、不计超期
            let dueDate = meeting.isAllDay ? nil : meeting.start
            if let i = todos.firstIndex(where: { $0.source == .calendar && $0.calendarEventId == key }) {
                todos[i].title = meeting.title
                todos[i].dueDate = dueDate
                // 提醒在外部（Apple 提醒事项）被勾掉 → 本地任务跟随完成。
                // 单向同步：EventKit 未完成不清本地完成态（不复活规则优先）
                if meeting.isCompleted, todos[i].completedAt == nil {
                    todos[i].completedAt = Date()
                }
            } else if !meeting.isCompleted {
                // 静默入库：日历同步每 15min 一轮，不播降落动效/通知卡；
                // 外部已完成的提醒不再生成任务（只在日历页签打勾展示）
                todos.append(Todo(title: meeting.title, source: .calendar,
                                  dueDate: dueDate, calendarEventId: key))
            }
        }
    }

    /// todo 对应「提醒事项」时返回其 EventKit 标识（回写判定用；日历事件返回 nil）
    private func reminderEventId(of todo: Todo) -> String? {
        guard todo.source == .calendar, let key = todo.calendarEventId,
              meetings.contains(where: { $0.eventIdentifier == key && $0.isReminder })
        else { return nil }
        return key
    }

    /// 日历页签完成标识：提醒事项以 EventKit 完成态为准（回写后/外部勾选都能立即反映）；
    /// 日历事件按对应 `.calendar` 任务匹配，限定今日——重复事件跨天共享
    /// eventIdentifier，其他天的实例不该跟着打勾
    func isMeetingCompleted(_ meeting: Meeting) -> Bool {
        if meeting.isCompleted { return true }
        guard Calendar.current.isDateInToday(meeting.start),
              let key = meeting.eventIdentifier else { return false }
        return todos.contains { $0.source == .calendar && $0.calendarEventId == key && $0.isCompleted }
    }

    /// 外部 ticket 源同步（Jira / GitHub PR 共用）：按 jiraKey 合并 + 按来源镜像清理。
    /// - Parameters:
    ///   - source: 本批数据的来源，清理只作用于该来源（github 不会清 jira）
    ///   - notify: true 且 island 处于 compact 态时，新分配弹通知卡
    ///     （jira-landed-card spec）；启动后首轮同步传 false 避免初始全量误报。
    ///   - prune: 镜像清理（jira-sync-prune spec）——本地未完成的同来源 todo
    ///     若 key 不在本次结果中则移除（被转走/关闭/合并）。要求 fetched 是
    ///     完整拉取结果；Debug 的 Mock 注入传 false，避免清掉真实数据。
    func mergeExternalTodos(_ fetched: [Todo], source: TodoSource, notify: Bool = true, prune: Bool = true) {
        if prune {
            let fetchedKeys = Set(fetched.compactMap(\.jiraKey))
            todos.removeAll { todo in
                guard todo.source == source, !todo.isCompleted, let key = todo.jiraKey else { return false }
                return !fetchedKeys.contains(key)
            }
        }
        let knownKeys = Set(todos.compactMap(\.jiraKey))
        var landed: [Todo] = []
        for ticket in fetched where ticket.jiraKey != nil {
            if let i = todos.firstIndex(where: { $0.jiraKey == ticket.jiraKey }) {
                // 外部源只读集成，服务器是唯一真相：派生字段以本次拉取为准
                todos[i].jiraStatus = ticket.jiraStatus
                todos[i].jiraStatusCategory = ticket.jiraStatusCategory
                todos[i].title = ticket.title
                todos[i].priority = ticket.priority
                todos[i].dueDate = ticket.dueDate
                todos[i].jiraAssigner = ticket.jiraAssigner
                todos[i].storyPoints = ticket.storyPoints
            } else if !knownKeys.contains(ticket.jiraKey!) {
                add(ticket)
                landed.append(ticket)
            }
        }
        // 新分配通知卡：不打断展开态/其他卡片态（静默入库，涟漪仍播放）
        if notify, let first = landed.first, islandState.isCompact {
            present(.jiraLanded(todo: first, moreCount: landed.count - 1))
        }
    }

    /// 兼容包装：既有调用方（轮询/刷新/Debug）继续可用
    func mergeJiraTodos(_ fetched: [Todo], notify: Bool = true, prune: Bool = true) {
        mergeExternalTodos(fetched, source: .jira, notify: notify, prune: prune)
    }

    // MARK: - 消息（message-inbox spec）

    /// 消息列表按接收时间倒序（消息页签消费）
    var sortedMessages: [Message] { messages.sorted { $0.receivedAt > $1.receivedAt } }

    /// 未处理消息数（消息页签角标）
    var unprocessedMessageCount: Int { messages.lazy.filter { !$0.isProcessed }.count }

    /// 演示邮件 messageId（MockEmailService 固定前缀）：用于启动时清掉历史落盘的假数据
    static func isDemoMessageId(_ id: String) -> Bool {
        ["slack-demo", "jira-demo", "email-demo", "urgent-"].contains { id.hasPrefix($0) }
    }

    /// 合并新消息：按 messageId 去重（已存在的保留已处理状态不覆盖）。
    /// notify 且 compact 态时，新消息弹降落通知卡（同轮多条聚合为「N 条」）。
    func addMessages(_ incoming: [Message], notify: Bool = true) {
        let knownIds = Set(messages.map(\.messageId))
        var landed: [Message] = []
        for msg in incoming where !knownIds.contains(msg.messageId) {
            messages.append(msg)
            landed.append(msg)
        }
        guard !landed.isEmpty else { return }
        // 降落通知卡：不打断展开态/其他卡片态（静默入库，待回 compact 顺延）
        if notify, let first = landed.first, islandState.isCompact {
            present(.messageLanded(message: first, moreCount: landed.count - 1))
        }
        refreshCompactState()
    }

    /// 标记消息已处理（点击完成 / 点击跳转均调用）；幂等：已处理则不刷新时间
    func markProcessed(_ message: Message) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }),
              messages[i].processedAt == nil else { return }
        messages[i].processedAt = Date()
    }

    /// 邮箱应用密码 —— 走 Keychain，不落明文 settings.json（design D7）。
    /// 计算属性：读取即查钥匙串，写入即存/删并通知 UI 刷新。
    private static let emailPasswordAccount = "emailAppPassword"
    var emailAppPassword: String {
        get { Keychain.load(account: Self.emailPasswordAccount) ?? "" }
        set {
            objectWillChange.send()
            Keychain.save(newValue, account: Self.emailPasswordAccount)
        }
    }

    // MARK: - 持久化

    private func persistTodos() {
        Persistence.save(todos, to: "todos.json")
    }

    /// 重置为演示数据（Debug 菜单 / Demo 翻车兜底）
    func resetDemoData() {
        crownedToday = false
        todos = Self.demoTodos()
        meetings = Self.demoMeetings()
        UserDefaults.standard.removeObject(forKey: "calendarInitialSyncCompleted")
        dismiss()
    }

    // MARK: - 演示数据（与 prototype.html 一致）

    static func demoTodos() -> [Todo] {
        let cal = Calendar.current
        let today18 = cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        let friday = cal.date(byAdding: .day, value: 3, to: Date())!
        return [
            Todo(title: "提交 PRD 草稿", source: .screenshot, priority: .high,
                 dueDate: today18, aiExplanation: "检测到「今晚之前」关键词 → 紧急"),
            Todo(title: "买生日礼物", source: .manual, priority: .medium, dueDate: friday),
            Todo(title: "健身打卡", source: .manual, priority: .low, tags: ["每天"]),
            Todo(title: "整理本周会议纪要", source: .manual, priority: .low, dueDate: friday),
            Todo(title: "修复登录 bug", source: .jira, priority: .high,
                 jiraKey: "MD-1024", jiraURL: URL(string: "https://example.atlassian.net/browse/MD-1024"),
                 jiraStatus: "In Progress"),
            Todo(title: "优化首页加载", source: .jira, priority: .medium,
                 jiraKey: "MD-1031", jiraURL: URL(string: "https://example.atlassian.net/browse/MD-1031"),
                 jiraStatus: "To Do"),
            Todo(title: "用户反馈调研", source: .jira, priority: .low,
                 jiraKey: "MD-1042", jiraURL: URL(string: "https://example.atlassian.net/browse/MD-1042"),
                 jiraStatus: "To Do"),
        ]
    }

    static func demoMeetings() -> [Meeting] {
        let cal = Calendar.current
        let m1Start = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        let m2Start = cal.date(bySettingHour: 15, minute: 0, second: 0, of: Date())!
        return [
            Meeting(title: "产品评审", start: m1Start, end: m1Start.addingTimeInterval(3600),
                    link: URL(string: "https://zoom.us/j/123456789"), platform: .zoom,
                    attendees: ["陈昊", "林嘉"], calendarName: "工作"),
            Meeting(title: "周会", start: m2Start, end: m2Start.addingTimeInterval(1800),
                    link: URL(string: "https://meeting.tencent.com/dm/abc"), platform: .tencent,
                    attendees: ["全员"], calendarName: "工作"),
        ]
    }
}

// MARK: - 统一动画（island-shell spec：所有形态切换用同一弹簧）

enum IslandAnimation {
    // response 0.38 / damping 0.8：比默认更跟手、轻微回弹不过冲，
    // 与内容浮现的 delay(0.1)+0.18s 时序衔接（IslandTransition）
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)
}
