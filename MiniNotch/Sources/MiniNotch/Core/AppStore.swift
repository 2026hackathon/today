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
    @Published var settings = AppSettings() { didSet { Persistence.save(settings, to: "settings.json") } }

    // MARK: - Island 状态

    @Published private(set) var islandState: IslandState = .normal
    /// AI 是否工作中（驱动 aiWorking 态 + 流光）
    @Published var isAIWorking = false { didSet { refreshCompactState() } }
    /// 今日全部完成后 compact 显示皇冠
    @Published private(set) var crownedToday = false

    /// 状态变化的副作用回调（动效/庆祝窗口挂这里，由 AppDelegate 装配）
    var onCompletedAll: (() -> Void)?
    var onTodoCompleted: ((Todo) -> Void)?
    var onTodoLanded: ((Todo) -> Void)?
    /// 手动刷新的实际同步逻辑（Jira/日历），AppDelegate 装配
    var onRefresh: (() async -> Void)?

    /// 刷新进行中（刷新按钮转圈用）
    @Published private(set) var isRefreshing = false

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
        if let saved = Persistence.load(AppSettings.self, from: "settings.json") {
            settings = saved
        }
        refreshCompactState()
    }

    // MARK: - 状态机操作

    /// 切换到事件态（卡片/展开/晨晚报）
    func present(_ state: IslandState) {
        withAnimation(IslandAnimation.spring) { islandState = state }
    }

    /// 回落到自动派生的 compact 态
    func dismiss() {
        withAnimation(IslandAnimation.spring) { islandState = derivedCompactState() }
    }

    /// 数据变化后刷新 compact 态（仅当前处于 compact 时生效，不打断卡片/展开态）
    func refreshCompactState() {
        guard islandState.isCompact else { return }
        let derived = derivedCompactState()
        if derived != islandState {
            withAnimation(IslandAnimation.spring) { islandState = derived }
        }
    }

    private func derivedCompactState() -> IslandState {
        if isAIWorking { return .aiWorking }
        if crownedToday && pendingTodos.allSatisfy({ $0.source == .jira }) { return .celebrate }
        guard let nearest = nextDue else {
            return pendingTodos.isEmpty ? .idle : .normal
        }
        let interval = nearest.timeIntervalSinceNow
        if interval < 30 * 60 { return .urgent }   // 30min 内 / 已过期
        if interval < 60 * 60 { return .near }     // 1h 内
        return .normal
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

    // MARK: - 今日焦点派生（today-focus-redesign spec）
    // Today 只回答「我今天要关注什么」：按时间相关性筛选，来源只是行内标识。

    /// Jira 活跃状态 = 非 To Do / Done / Cancelled（用户正在做的才算今天的事）
    private static let jiraInactiveStatuses: Set<String> = [
        "to do", "todo", "open", "backlog", "done", "cancelled", "canceled", "closed",
    ]

    private func isActiveJira(_ todo: Todo) -> Bool {
        guard todo.source == .jira else { return false }
        let status = (todo.jiraStatus ?? "").lowercased()
        return !Self.jiraInactiveStatuses.contains(status)
    }

    /// 已超期：个人来源全部计入；Jira 仅活跃状态计入（陈年 To Do 的过期 duedate 是噪音）
    var overdueTodos: [Todo] {
        sorted(pendingTodos.filter { $0.isOverdue && ($0.source != .jira || isActiveJira($0)) })
    }

    /// 今日任务·有时间：今天截止未超期（含 Snooze 今天到点），按时间排
    var todayTimedTodos: [Todo] {
        pendingTodos
            .filter { todo in
                guard !todo.isOverdue else { return false }
                if todo.source == .jira, !isActiveJira(todo) { return false }
                let anchor = todo.snoozedUntil ?? todo.dueDate
                guard let anchor else { return false }
                return Calendar.current.isDateInToday(anchor)
            }
            .sorted { ($0.snoozedUntil ?? $0.dueDate!) < ($1.snoozedUntil ?? $1.dueDate!) }
    }

    /// 今日任务·无固定时间：活跃 Jira（无今日截止的）+ 无截止的个人任务，按优先级排
    var todayUntimedTodos: [Todo] {
        let timedIDs = Set(todayTimedTodos.map(\.id))
        let overdueIDs = Set(overdueTodos.map(\.id))
        return sorted(pendingTodos.filter { todo in
            guard !timedIDs.contains(todo.id), !overdueIDs.contains(todo.id) else { return false }
            if todo.source == .jira { return isActiveJira(todo) }
            // GitHub PR：待 review / 已指派本身就是「当下要处理」，恒入今日任务
            if todo.source == .github { return true }
            return todo.dueDate == nil
        })
    }

    /// Inbox（全部任务视图）：未来截止 + To Do 状态 Jira —— 今日焦点之外的所有未完成项
    var inboxTodos: [Todo] {
        let focusIDs = Set((overdueTodos + todayTimedTodos + todayUntimedTodos).map(\.id))
        return sorted(pendingTodos.filter { !focusIDs.contains($0.id) })
    }

    /// 今日焦点数（compact 计数 / 问候语用，与 Today 面板一致）
    var todayFocusCount: Int {
        overdueTodos.count + todayTimedTodos.count + todayUntimedTodos.count
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
        todos.removeAll { $0.id == todo.id }
        refreshCompactState()
    }

    func complete(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].completedAt = Date()
        completionFlash += 1
        onTodoCompleted?(todos[i])

        // 周期任务（每天/每周X）：完成本次后自动排下一次
        // （在庆祝判断之前 append，周期任务不算"清零"）
        if let next = Self.nextOccurrence(of: todos[i]) {
            todos.append(next)
        }

        // Jira 是只读集成不可完成，庆祝以「个人 Todo 清零」为准
        if pendingTodos.allSatisfy({ $0.source == .jira }) {
            // 完成今日全部 → 全屏庆祝 + 皇冠（effects spec）
            crownedToday = true
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
        dismiss()
    }

    /// 完成单个后的 1s 金色闪光，随后回落
    private func flashJustCompleted() {
        completedFlashTask?.cancel()
        withAnimation(IslandAnimation.spring) { islandState = .justCompleted }
        completedFlashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    // MARK: - Meeting 同步（CalendarService 调用）

    func replaceMeetings(_ new: [Meeting]) {
        meetings = new
        refreshCompactState()
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

    // MARK: - 持久化

    private func persistTodos() {
        Persistence.save(todos, to: "todos.json")
    }

    /// 重置为演示数据（Debug 菜单 / Demo 翻车兜底）
    func resetDemoData() {
        crownedToday = false
        todos = Self.demoTodos()
        meetings = Self.demoMeetings()
        dismiss()
    }

    // MARK: - 演示数据（与 prototype.html 一致）

    static func demoTodos() -> [Todo] {
        let cal = Calendar.current
        let today18 = cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        let friday = cal.date(byAdding: .day, value: 3, to: Date())!
        return [
            Todo(title: "提交 PRD 草稿", source: .screenshot, priority: .high,
                 dueDate: today18, aiExplanation: "检测到「今晚之前」关键词 → 紧急"),
            Todo(title: "买生日礼物", source: .manual, priority: .medium, dueDate: friday),
            Todo(title: "健身打卡", source: .manual, priority: .low, tags: ["每天"]),
            Todo(title: "回复客户邮件", source: .wechat, priority: .medium, dueDate: tomorrow),
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
