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
    /// 外部工单（Jira ticket / GitHub PR）——只读、轮询替换，独立于个人 Todo（work-item spec）
    @Published private(set) var workItems: [WorkItem] = [] { didSet { Persistence.save(workItems, to: "workItems.json") } }
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
    /// Debug 预览：强制 urgent 走红色（过期）光，绕开"必须真有超期项"的条件。仅 Debug 菜单用。
    @Published var debugForceRedGlow = false
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
    static let defaultTabs: [PanelTab] = [.today, .workItems, .messages, .agent, .calendar]
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

    /// 快速录入里 ⌘V 贴图后回车：直接拿 PNG（可多张）走截图 AI 流水线（AppDelegate 装配）
    var onRecognizeImages: (([Data]) -> Void)?

    /// 识别已贴入快速录入框的截图（一张或多张，归到同一条任务）
    func recognizeImages(_ data: [Data]) { onRecognizeImages?(data) }

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
            // 非空才覆盖，保留已有值（Stop 不带 prompt、UserPromptSubmit 不带 name/answer）。
            // title（你的提问）只在首次为空时落地——保留「会话首条 prompt」作主题，
            // 不被后续的「继续」「按你推荐的来」等无信息量的追问覆盖。
            if let t = event.title, !t.isEmpty, (agentSessions[i].title ?? "").isEmpty {
                agentSessions[i].title = t
            }
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

    /// 陈旧清理：任何状态超 30min 无任何 hook 事件即视为已死/已弃，移除。
    /// 统一阈值（原 waiting/replied 用 6h，导致关掉终端后的「待确认」残留长达数小时、
    /// 堆在 Agent 面板里）——Claude/opencode 真正活跃时持续有事件刷新 updatedAt，
    /// 30min 静默基本等同会话已结束/终端已关。正常退出仍优先靠 SessionEnd 即时移除。
    func sweepStaleAgentSessions(now: Date = Date()) {
        agentSessions.removeAll { now.timeIntervalSince($0.updatedAt) > 30 * 60 }
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
    /// 确认弹窗（删除苹果日程/提醒的二次确认）打开计数——>0 时悬停移出不自动收起，
    /// 否则鼠标移向弹窗按钮途中离开悬停区会把弹窗一起收掉。各行 confirmationDialog 对称 +1/-1。
    @Published var dialogPresentedCount = 0
    /// 截图大图查看器（盖在岛上层的模态）打开中——看图是一次聚焦模态，期间灵动岛保持不动、
    /// 不自动收起；查看器关闭时由其生命周期回调清零，恢复正常悬停/失焦收起。
    @Published var screenshotViewerOpen = false

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
    /// Touchdown 涟漪色：个人任务落地用来源色，工单（Jira/GitHub）落地用工单来源色；播完自清
    @Published var landedRippleColor: Color?
    /// 完成计数器：递增一次 = 播一次金色高光 + 撒花
    @Published private(set) var completionFlash = 0

    private var completedFlashTask: Task<Void, Never>?

    init() {
        // 首次启动从空开始，不种演示数据；演示数据只通过
        // Debug 菜单「重置演示数据」显式载入（Demo 兜底）
        // 旧版本曾把 Jira/GitHub 当 Todo 落盘（source .jira/.github + jiraKey，现已抽成 WorkItem）。
        // 删掉这些枚举值后，旧记录解码会把 source 回退成 .manual 变“幽灵任务”，
        // 故在解码前按原始 JSON 剔除（source 为 jira/github 或含 jiraKey 的条目）。
        todos = Self.loadTodosDroppingLegacyExternal()
        workItems = Persistence.load([WorkItem].self, from: "workItems.json") ?? []
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

    // MARK: - 提前准备徽章（prep-reminder-card spec）
    // 瞬态、不持久化：提前准备是当下窗口的事，重启自然清空。
    // 仅高优先级 lead 触发后入集合 → compact 显示常驻徽章；中/低不入集合。

    @Published private(set) var prepPendingTodoIDs: Set<UUID> = []

    /// 有任意待准备项 → compact 显示提前准备徽章
    var hasPrepBadge: Bool { !prepPendingTodoIDs.isEmpty }
    var prepBadgeCount: Int { prepPendingTodoIDs.count }

    /// lead（提前量）到点：高优先级入集合（留徽章），按输入态护栏决定是否弹卡。
    /// 低优先级不应调此方法（AppDelegate 只对中/高调用）。聚合与 moreCount 在此集中处理。
    func presentPrep(_ todo: Todo) {
        if todo.priority == .high { prepPendingTodoIDs.insert(todo.id) }
        switch islandState {
        case .quickInput, .newTask, .batch: return   // 不抢占输入态（徽章已就位）
        case .prepReminder: return                    // 已在展示 prep 卡，其余只进徽章不重复弹
        default: break
        }
        // moreCount = 其余待准备（徽章中）项数：高优先级排除自身
        let more = max(0, prepBadgeCount - (todo.priority == .high ? 1 : 0))
        present(.prepReminder(todo: todo, moreCount: more))
    }

    /// 高优先级「知道了」/点外侧：收卡回落，id 仍在集合 → compact 留徽章
    func acknowledgePrep(_ todo: Todo) { dismiss() }

    /// 点击提前准备徽章：重新展开最紧近一项 prep 卡
    func reopenPrep() {
        prunePrepBadges()
        let pending = todos.filter { prepPendingTodoIDs.contains($0.id) && !$0.isCompleted }
        guard let next = pending.min(by: {
            ($0.effectiveDue ?? .distantFuture) < ($1.effectiveDue ?? .distantFuture)
        }) else { return }
        present(.prepReminder(todo: next, moreCount: max(0, pending.count - 1)))
    }

    /// 提醒接管（fifteenMin/due/overdue）/ 完成 / 删除时清除徽章
    func clearPrep(_ todo: Todo) { prepPendingTodoIDs.remove(todo.id) }

    /// 自动清除兜底：仅保留「仍存在、未完成、未被 snooze 压住、且距有效截止 > finalWindow」的项
    func prunePrepBadges() {
        guard !prepPendingTodoIDs.isEmpty else { return }
        let now = Date()
        prepPendingTodoIDs = prepPendingTodoIDs.filter { id in
            guard let t = todos.first(where: { $0.id == id }), !t.isCompleted else { return false }
            if let snooze = t.snoozedUntil, snooze > now { return false }
            guard let anchor = t.snoozedUntil ?? t.dueDate else { return false }
            return anchor.timeIntervalSince(now) > Double(t.finalWindowMinutes * 60)
        }
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
        prunePrepBadges()   // 数据变化时兜底清除已失效的提前准备徽章
        guard islandState.isCompact else { return }
        let derived = derivedCompactState()
        if derived != islandState {
            withAnimation(IslandAnimation.spring) { islandState = derived }
        }
    }

    private func derivedCompactState() -> IslandState {
        if isAIWorking { return .aiWorking }
        // 个人可动手的事清零即可加冕/打钩——只读工作项（Jira/GitHub）不算「可动手」，不阻塞
        if crownedToday && todayActionableCount == 0 { return .celebrate }
        guard todayActionableCount > 0 else { return .idle }

        // 逐任务按各自 AI 提前量判定高亮：会议（提前量大）更早进入 near/urgent，
        // 吃饭喝水（提前量小）只在临近才亮 —— 不再全局一刀切 60/15min
        let endOfToday = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        var level = 0 // 0 normal · 1 near · 2 urgent
        for todo in pendingTodos {
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

    /// 个人待办（Todo 现已全是个人来源——外部工单见 workItems）
    var personalTodos: [Todo] { sorted(pendingTodos) }
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
    // 外部工单（Jira/GitHub）已抽成 WorkItem，见下方 activeWorkItems / inboxWorkItems。

    /// 已超期：截止已过的未完成个人任务（外部工单不计入超期）
    var overdueTodos: [Todo] {
        sorted(pendingTodos.filter { $0.isOverdue })
    }

    /// 今日任务·有时间：可完成的个人任务，今天截止未超期（含 Snooze 今天到点），按时间排
    var todayTimedTodos: [Todo] {
        pendingTodos
            .filter { todo in
                guard !todo.isOverdue else { return false }
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
            guard !overdueIDs.contains(todo.id) else { return false }
            return todo.dueDate == nil
        })
    }

    // MARK: - WorkItem 派生（work-item spec）

    /// 活跃工作项（进 Today「工作项」分组）：Jira In Progress 类 + GitHub 待 review/已指派
    var activeWorkItems: [WorkItem] {
        workItems.filter(\.isActive).sorted { $0.priority.sortRank < $1.priority.sortRank }
    }

    /// 非活跃工作项（进 Later/Inbox）：To Do/Backlog 等
    var inboxWorkItems: [WorkItem] {
        workItems.filter { !$0.isActive }.sorted { $0.priority.sortRank < $1.priority.sortRank }
    }

    /// Calendar 页签承载的本地个人任务（later-into-calendar）：本地创建（含已完成）。
    /// 排除 `.calendar` 来源——后者已作为 Meeting 展示，避免重复。
    var calendarPersonalTodos: [Todo] {
        sorted(todos.filter { $0.source != .calendar })
    }

    /// 今日焦点数（Today 面板问候语用，与面板列表一致，含活跃工作项）
    var todayFocusCount: Int {
        overdueTodos.count + todayTimedTodos.count + todayUntimedTodos.count + activeWorkItems.count
    }

    /// 今日「可动手」数（compact 计数与打钩判定用）：只算个人任务——
    /// 工作项只读会挂很多天，个人的事做完了刘海就该打钩
    var todayActionableCount: Int {
        overdueTodos.count + todayTimedTodos.count + todayUntimedTodos.count
    }
    var completedToday: [Todo] {
        todos.filter {
            guard let done = $0.completedAt else { return false }
            return Calendar.current.isDateInToday(done)
        }
    }

    var reportContext: ReportContext {
        ReportContext(pendingTodos: pendingTodos, workItems: workItems,
                      completedToday: completedToday, meetings: todayMeetings)
    }

    // MARK: - Todo CRUD

    func add(_ todo: Todo) {
        todos.append(todo)
        onTodoLanded?(todo)
        if settings.effectsEnabled {
            landedRippleColor = DS.sourceColor(todo.source)
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

    /// 删除可用性：Todo 现已全是本地/苹果来源，均可删（外部工单是 WorkItem，不走这里）。
    func canDelete(_ todo: Todo) -> Bool { true }

    func complete(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].completedAt = Date()
        completionFlash += 1
        prepPendingTodoIDs.remove(todo.id)   // 完成即清除其提前准备徽章
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

        // 工作项是只读集成不可完成，庆祝以「个人 Todo 清零」为准
        if pendingTodos.isEmpty {
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
            // 苹果来源 kind：提醒事项→提醒、日历事件→日程（驱动 kind 标签与默认提前量）
            let kind: DraftKind = meeting.isReminder ? .reminder : .event
            if let i = todos.firstIndex(where: { $0.source == .calendar && $0.calendarEventId == key }) {
                todos[i].title = meeting.title
                todos[i].dueDate = dueDate
                todos[i].kind = kind
                // 提醒在外部（Apple 提醒事项）被勾掉 → 本地任务跟随完成。
                // 单向同步：EventKit 未完成不清本地完成态（不复活规则优先）
                if meeting.isCompleted, todos[i].completedAt == nil {
                    todos[i].completedAt = Date()
                }
            } else if !meeting.isCompleted {
                // 静默入库：日历同步每 15min 一轮，不播降落动效/通知卡；
                // 外部已完成的提醒不再生成任务（只在日历页签打勾展示）
                todos.append(Todo(title: meeting.title, source: .calendar, kind: kind,
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

    /// 外部工单源同步（Jira / GitHub PR 共用）：按 key upsert + 按来源镜像清理（work-item spec）。
    /// - Parameters:
    ///   - source: 本批数据的来源，清理只作用于该来源（github 不会清 jira）
    ///   - notify: true 且 island 处于 compact 态时，新分配弹通知卡
    ///     （jira-landed-card spec）；启动后首轮同步传 false 避免初始全量误报。
    ///   - prune: 镜像清理——本地同来源工作项若 key 不在本次结果中则移除
    ///     （被转走/关闭/合并）。要求 fetched 完整；Debug Mock 注入传 false。
    func mergeWorkItems(_ fetched: [WorkItem], source: WorkItemSource, notify: Bool = true, prune: Bool = true) {
        if prune {
            let fetchedKeys = Set(fetched.map(\.key))
            workItems.removeAll { $0.source == source && !fetchedKeys.contains($0.key) }
        }
        let knownKeys = Set(workItems.map(\.key))
        var landed: [WorkItem] = []
        for item in fetched {
            if let i = workItems.firstIndex(where: { $0.key == item.key }) {
                // 外部源只读集成，服务器是唯一真相：整条以本次拉取为准
                workItems[i] = item
            } else if !knownKeys.contains(item.key) {
                workItems.append(item)
                landed.append(item)
            }
        }
        refreshCompactState()
        // 新分配通知卡：不打断展开态/其他卡片态（静默入库）
        if notify, let first = landed.first, islandState.isCompact {
            if settings.effectsEnabled { landedRippleColor = DS.workItemColor(first.source) }
            present(.jiraLanded(item: first, moreCount: landed.count - 1))
        }
    }

    /// 兼容包装：Jira 轮询/刷新/Debug 调用
    func mergeJiraWorkItems(_ fetched: [WorkItem], notify: Bool = true, prune: Bool = true) {
        mergeWorkItems(fetched, source: .jira, notify: notify, prune: prune)
    }

    // MARK: - 消息（message-inbox spec）

    /// 消息列表按接收时间倒序（消息页签消费）
    var sortedMessages: [Message] { messages.sorted { $0.receivedAt > $1.receivedAt } }

    /// 未处理邮件按收件自然天分组：组间按天倒序、组内按 receivedAt 倒序，仅保留最近 3 个收件日
    var pendingMessagesByDay: [(day: Date, messages: [Message])] {
        Self.groupByDay(messages.filter { !$0.isProcessed })
    }

    /// 已处理邮件按收件自然天分组：规则同 pendingMessagesByDay
    var processedMessagesByDay: [(day: Date, messages: [Message])] {
        Self.groupByDay(messages.filter { $0.isProcessed })
    }

    /// 按 startOfDay(receivedAt) 分组，组间日期倒序、组内 receivedAt 倒序，取最近 3 个收件日
    private static func groupByDay(_ msgs: [Message]) -> [(day: Date, messages: [Message])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: msgs) { cal.startOfDay(for: $0.receivedAt) }
        return grouped
            .map { (day: $0.key, messages: $0.value.sorted { $0.receivedAt > $1.receivedAt }) }
            .sorted { $0.day > $1.day }
            .prefix(3)
            .map { $0 }
    }

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

    /// 解码 todos.json，但在解码前剔除旧版遗留的外部工单记录（source jira/github 或含 jiraKey）。
    /// 否则删掉枚举值后这些项会回退成 .manual 变“幽灵任务”。外部工单由轮询重建为 WorkItem。
    static func loadTodosDroppingLegacyExternal() -> [Todo] {
        let url = Persistence.baseDir.appendingPathComponent("todos.json")
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return Persistence.load([Todo].self, from: "todos.json") ?? []
        }
        let cleaned = raw.filter { dict in
            if let src = dict["source"] as? String, src == "jira" || src == "github" { return false }
            if dict["jiraKey"] is String { return false }
            return true
        }
        guard let reData = try? JSONSerialization.data(withJSONObject: cleaned) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Todo].self, from: reData)) ?? []
    }

    /// 重置为演示数据（Debug 菜单 / Demo 翻车兜底）
    func resetDemoData() {
        crownedToday = false
        todos = Self.demoTodos()
        workItems = Self.demoWorkItems()
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
        ]
    }

    /// 演示工作项（Debug 重置时与 demoTodos 一起载入，对应原 demo 里的 Jira 条目）
    static func demoWorkItems() -> [WorkItem] {
        [
            WorkItem(key: "MD-1024", title: "修复登录 bug", source: .jira,
                     status: "In Progress", statusCategory: "indeterminate",
                     url: URL(string: "https://example.atlassian.net/browse/MD-1024"), priority: .high),
            WorkItem(key: "MD-1031", title: "优化首页加载", source: .jira,
                     status: "To Do", statusCategory: "new",
                     url: URL(string: "https://example.atlassian.net/browse/MD-1031"), priority: .medium),
            WorkItem(key: "MD-1042", title: "用户反馈调研", source: .jira,
                     status: "To Do", statusCategory: "new",
                     url: URL(string: "https://example.atlassian.net/browse/MD-1042"), priority: .low),
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
