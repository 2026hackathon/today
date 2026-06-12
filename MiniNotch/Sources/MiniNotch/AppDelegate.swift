import AppKit
import Combine
import EventKit
import SwiftUI

// ============================================================
// AppDelegate —— 全应用唯一装配点。
// 换真实现只改 makeServices()；新增副作用只在 wireServices() 挂。
// ============================================================

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var statusItem: NSStatusItem?

    private let store = AppStore()

    // MARK: - 服务（换真实现改这里 —— 见 docs/MODULES.md）

    /// Mock 常驻：AI 配置不全时兜底（CODING_GUIDELINES：保留 Mock）
    private let mockAIService = MockAIService()
    private lazy var captureService: CaptureService = HotkeyCaptureService() // owner C
    /// Mock 常驻：配置不全时兜底 + Debug「模拟 Jira 新分配」演示
    private let mockJiraService = MockJiraService()
    /// Mock 常驻：配置不全时兜底 + Debug「模拟 PR 新分配」演示
    private let mockGitHubService = MockGitHubService()
    /// EventKit 真实日历服务（权限就绪时使用；被拒/失败 → 上层按空列表处理，不用 Mock 填充）
    private let eventKitCalendarService = EventKitCalendarService()
    private lazy var reminderScheduler: ReminderScheduler = TimerReminderScheduler()
    private lazy var pushService: PushService = NoopPushService()     // owner C: 按 settings 换 Feishu/Bark

    /// 外部源同步基线：首次「成功」同步后置位，之后的新 key 才弹通知卡。
    /// 失败不置位（review-fixes #2：否则首轮断网 → 第二轮全量误报为新分配）
    private var jiraBaselineSynced = false
    private var githubBaselineSynced = false
    /// 未配置时的清空只在启动后第一次同步执行（清历史 Mock/旧数据）；
    /// 运行期未配置多半是用户正在设置页编辑凭证，跳过同步避免 prune
    /// 误删真实数据（review-fixes #1）
    private var didLaunchCleanupJira = false
    private var didLaunchCleanupGitHub = false

    private var cancellables = Set<AnyCancellable>()
    private var pollingTasks: [Task<Void, Never>] = []
    private var clickOutsideMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory 模式：不占 Dock、不出现在 ⌘Tab 切换里
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()
        installEditMenu()
        showPanel()
        setupDismissOnFocusLoss()
        setupMenuTrackingObserver()
        setupKeyboardFocusForInputStates()
        wireServices()
        requestCalendarAccess()    // accessory 应用需临时激活才能弹权限弹窗
        startPolling()
        maybeShowMorningReport()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTasks.forEach { $0.cancel() }
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - 失焦收起（island-shell spec：展开/卡片态点击外部回落 compact）

    private func setupDismissOnFocusLoss() {
        // 全局监听只收到「本应用之外」的鼠标按下 —— 即点到了其他软件/桌面。
        // 点击 island 自身走的是本地事件，不会触发这里
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismissOnFocusLoss() }
        }

        // ⌘Tab / Spotlight 等不经鼠标点击切走焦点的情况
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activated?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in self?.dismissOnFocusLoss() }
        }
    }

    /// 任意 NSMenu（Debug 菜单/右键菜单/卡内 Menu）跟踪期间，
    /// 悬停收起与卡片倒计时让路（review-fixes #12）
    private func setupMenuTrackingObserver() {
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.store.isMenuTracking = true }
        }
        NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.store.isMenuTracking = false }
        }
    }

    private func dismissOnFocusLoss() {
        guard store.islandState.isDismissable else { return }
        store.dismiss()
    }

    // MARK: - 输入态键盘支持（⌘V 粘贴等）

    /// ⌘V/⌘C 等编辑快捷键经由主菜单的 Edit 菜单分发——accessory 应用默认没有
    /// 主菜单，必须手动装载，否则 SwiftUI 输入框收不到粘贴指令
    private func installEditMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    /// 进入需要打字的状态（设置页 / ⌘N 快速录入）时激活应用：
    /// 菜单快捷键只对「活跃应用」分发，nonactivating 面板光成为 key window 不够。
    /// 只在输入态激活，普通悬停展开不抢其他应用的焦点
    private func setupKeyboardFocusForInputStates() {
        store.$islandState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let needsKeyboard: Bool = switch state {
                case .quickInput, .expanded(tab: .settings): true
                default: false
                }
                if needsKeyboard {
                    NSApp.activate(ignoringOtherApps: true)
                    self.panel?.makeKey()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 服务装配

    private func wireServices() {
        // F2 截图 → AI 解析 → 任务降落 / 批量识别（ai-pipeline spec）
        captureService.onTodoCapture = { [weak self] data, path in
            guard let self else { return }
            self.store.isAIWorking = true
            Task { @MainActor in
                do {
                    var drafts = try await self.currentAIService().parseScreenshot(data)
                    for i in drafts.indices { drafts[i].screenshotPath = path }
                    self.store.isAIWorking = false
                    if drafts.count >= 3 {
                        self.store.present(.batch(drafts: drafts))
                    } else if let first = drafts.first {
                        self.store.present(.newTask(draft: first))
                    } else {
                        self.store.present(.quickInput) // 没识别到 → 手动录入兜底
                    }
                } catch {
                    NSLog("[AI] parse failed: \(error)")
                    self.store.isAIWorking = false
                    self.store.present(.quickInput)
                }
            }
        }
        // F3 收藏：文件已落盘 favorites/，收藏 Tab 待接入（capture spec / owner C）
        captureService.onFavoriteCapture = { path in
            NSLog("[Capture] favorited: \(path)") // TODO(C): 收藏 Tab + AI 打标签
        }
        captureService.start()

        // 到期提醒（reminders spec）：强提醒弹卡 + 推送，弱提醒只刷新 compact 色
        reminderScheduler.onFire = { [weak self] todo, level in
            guard let self else { return }
            switch level {
            case .due, .overdue:
                // 输入态不抢占（打字中的草稿无价）；推送照发，过期级 5 分钟后会再来
                switch self.store.islandState {
                case .quickInput, .newTask, .batch: break
                default: self.store.present(.reminder(todo: todo))
                }
                Task { await self.pushService.push(title: "⏰ 任务到期", body: todo.title) }
            case .oneHour, .fifteenMin:
                self.store.refreshCompactState()
            }
        }
        // 数据一变就重排提醒
        store.$todos
            .sink { [weak self] todos in
                guard let self else { return }
                let settings = self.store.settings
                self.reminderScheduler.reschedule(for: todos, quietCheck: { settings.isQuietHour($0) })
            }
            .store(in: &cancellables)

        // 任务/会议变化后重新生成 AI 建议（防抖 2s：连续完成/新建只打一次 LLM；
        // dropFirst 跳过启动时的初始赋值，首条建议由 launch 的延迟调用负责）
        Publishers.CombineLatest(store.$todos, store.$meetings)
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshAISuggestion() }
            .store(in: &cancellables)

        // 完成今日全部 → 全屏庆祝（effects spec）
        store.onCompletedAll = { [weak self] in
            guard let self, self.store.settings.effectsEnabled else { return }
            CelebrationWindowController.shared.celebrate(streakDays: self.bumpClearStreak())
        }

        // 手动刷新按钮 → 立即同步 Jira + 日历
        store.onRefresh = { [weak self] in
            await self?.syncExternalSources(notifyJira: true)
            self?.refreshAISuggestion()
        }

        // ── 日历三层同步（apple-calendar-integration spec）──
        // Layer 1: 事件驱动（EKEventStoreChanged → 即时刷新）—— 权限授予后才挂接
        // Layer 3: 前台刷新（展开面板时立即拉一次）
        store.$islandState
            .sink { [weak self] newState in
                guard case .expanded = newState else { return }
                Task { @MainActor in self?.refreshCalendarMeetings() }
            }
            .store(in: &cancellables)

        // 启动后等首轮 Jira/日历同步落地，再生成 Today 底部一句话建议
        refreshAISuggestion(afterSeconds: 3)
    }

    /// 生成 Today 面板顶部的 AI 一句话建议（失败保持现有/兜底文案）
    private func refreshAISuggestion(afterSeconds delay: Double = 0) {
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            if let text = try? await currentAIService().generateDailySuggestion(todaySuggestionContext()) {
                store.updateAISuggestion(text)
            }
        }
    }

    /// 建议条挂在 Today 面板上，只喂今日焦点数据（超期 + 今日任务 + 今日会议）。
    /// 喂全部 pendingTodos 会让 AI 建议 Inbox 里明天的事，和面板列表对不上
    private func todaySuggestionContext() -> ReportContext {
        ReportContext(
            pendingTodos: store.overdueTodos + store.todayTimedTodos + store.todayUntimedTodos,
            completedToday: store.completedToday,
            meetings: store.todayMeetings
        )
    }

    /// accessory 应用临时激活 → 请求日历权限 → 恢复 accessory。
    /// 不临时激活的话系统权限弹窗不会显示（LSUIElement 应用无前台权限）。
    private func requestCalendarAccess() {
        // 如果已有权限或被拒，不需要弹窗
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .notDetermined else {
            if status == .fullAccess {
                // 老用户路径不经过 requestAccess()，需补挂 EKEventStoreChanged 监听，
                // 否则外部改日程只能等 15min 兜底轮询
                eventKitCalendarService.startObservingIfAuthorized()
                wireCalendarLayer1()
                performInitialSyncIfNeeded()
                refreshCalendarMeetings() // 已有权限 → 立即拉一次
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // 临时切为 regular 激活策略（让系统允许弹窗）
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let granted = await self.eventKitCalendarService.requestAccess()

            // 恢复 accessory 模式（不占 Dock、不出现在 ⌘Tab）
            NSApp.setActivationPolicy(.accessory)
            // accessory 模式下需要重新 orderFront 面板
            self.panel?.orderFrontRegardless()

            if granted {
                self.wireCalendarLayer1()
                self.performInitialSyncIfNeeded()
                self.refreshCalendarMeetings()
            } else {
                NSLog("[Calendar] permission denied — meetings stay empty (no mock fill)")
            }
        }
    }

    /// 首次同步检查：如果从未完成过首次同步，执行 30 天窗口历史数据拉取
    private func performInitialSyncIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "calendarInitialSyncCompleted") else { return }
        NSLog("[Calendar] performing initial historical sync (30-day window)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let service = self.currentCalendarService() else { return }
            do {
                let range = CalendarSyncConfig.defaultRange()
                let meetings = try await service.fetchMeetings(in: range)
                self.store.replaceMeetings(meetings)
                UserDefaults.standard.set(true, forKey: "calendarInitialSyncCompleted")
                NSLog("[Calendar] initial sync complete: %d meetings", meetings.count)
            } catch {
                NSLog("[Calendar] initial sync failed: \(error) — will retry next launch")
            }
        }
    }

    /// 立即同步外部数据源（刷新按钮 / 轮询共用）
    private func syncExternalSources(notifyJira: Bool) async {
        await syncJira(notify: notifyJira)
        await syncGitHub(notify: notifyJira)
        // 日历：权限被拒/拉取失败 → 空列表（顺带清掉历史演示会议，不用 Mock 填充）
        var meetings: [Meeting] = []
        if let calendar = currentCalendarService() {
            meetings = (try? await calendar.fetchMeetings(in: CalendarSyncConfig.defaultRange())) ?? []
        }
        store.replaceMeetings(meetings)
    }

    /// 挂接 Layer 1 事件驱动回调（仅在权限授予后调用）
    private func wireCalendarLayer1() {
        eventKitCalendarService.onCalendarChanged = { [weak self] in
            Task { @MainActor in self?.refreshCalendarMeetings() }
        }
    }

    /// 拉取一次日历会议（三层同步共用入口）
    private func refreshCalendarMeetings() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let service = self.currentCalendarService() else {
                self.store.replaceMeetings([]) // 权限被拒 → 清空，不用 Mock 填充
                return
            }
            do {
                let range = CalendarSyncConfig.defaultRange()
                let meetings = try await service.fetchMeetings(in: range)
                let msg = "[Calendar] \(meetings.count) meetings, range=\(range.lowerBound.formatted(.dateTime.month().day()))~\(range.upperBound.formatted(.dateTime.month().day())), service=\(type(of: service))"
                NSLog("%@", msg)
                Self.appendCalLog(msg)
                self.store.replaceMeetings(meetings)
            } catch {
                let msg = "[Calendar] failed: \(error)"
                NSLog("%@", msg)
                Self.appendCalLog(msg)
            }
        }
    }

    private static func appendCalLog(_ msg: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/MiniNotch/calendar-debug.log")
        let line = "\(Date()): \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        } else {
            try? data.write(to: url)
        }
    }

    /// 按配置动态选择 Jira 服务：三项齐全 → Real，否则 → Mock。
    /// 每个轮询周期重新判定，设置面板改完即生效，无需重启（integrations spec delta）。
    /// AI：填了 Key 就走真实 AI（端点/模型用 AIDefaults 固定值，settings 留作隐藏覆盖口），否则 Mock
    private func currentAIService() -> AIService {
        let s = store.settings
        guard !s.aiAPIKey.isEmpty else { return mockAIService }
        return OpenAIChatAIService(
            baseURL: s.aiBaseURL.isEmpty ? AIDefaults.baseURL : s.aiBaseURL,
            apiKey: s.aiAPIKey,
            model: s.aiModel.isEmpty ? AIDefaults.model : s.aiModel
        )
    }

    /// 未配置 → nil（列表不再用 Mock 填充；Mock 仅供 Debug 菜单显式触发）
    private func currentJiraService() -> JiraService? {
        let s = store.settings
        guard !s.jiraBaseURL.isEmpty, !s.jiraEmail.isEmpty, !s.jiraAPIToken.isEmpty else { return nil }
        return RealJiraService(baseURL: s.jiraBaseURL, email: s.jiraEmail, apiToken: s.jiraAPIToken)
    }

    /// GitHub：Token 非空 → Real，否则 nil（同 Jira 规则）
    private func currentGitHubService() -> GitHubService? {
        let token = store.settings.githubToken
        return token.isEmpty ? nil : RealGitHubService(token: token)
    }

    /// 拉取一轮 Jira：未配置时合并空列表（prune 清掉历史 Mock/失效残留）
    private func syncJira(notify: Bool) async {
        guard let service = currentJiraService() else {
            if !didLaunchCleanupJira {
                didLaunchCleanupJira = true
                store.mergeJiraTodos([], notify: false)
            }
            return // 运行期未配置（编辑凭证窗口）：跳过，不 prune
        }
        didLaunchCleanupJira = true
        if let tickets = try? await service.fetchAssignedTickets() {
            store.mergeJiraTodos(tickets, notify: notify && jiraBaselineSynced)
            jiraBaselineSynced = true
        }
    }

    /// 拉取一轮 GitHub PR：未配置时合并空列表（prune 清残留）
    private func syncGitHub(notify: Bool) async {
        guard let service = currentGitHubService() else {
            if !didLaunchCleanupGitHub {
                didLaunchCleanupGitHub = true
                store.mergeExternalTodos([], source: .github, notify: false)
            }
            return // 运行期未配置：跳过，不 prune（review-fixes #1）
        }
        didLaunchCleanupGitHub = true
        if let prs = try? await service.fetchMyPullRequests() {
            store.mergeExternalTodos(prs, source: .github, notify: notify && githubBaselineSynced)
            githubBaselineSynced = true
        }
    }

    /// 按 EventKit 权限动态选择日历服务。
    /// - fullAccess / notDetermined → EventKit（notDetermined 时首次拉取会弹权限弹窗）
    /// - denied / restricted → nil（权限被拒 → 空列表，不用 Mock 填充）
    private func currentCalendarService() -> CalendarService? {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .denied, .restricted:
            return nil
        default: // .fullAccess, .notDetermined
            return eventKitCalendarService
        }
    }

    /// Jira + GitHub（间隔共用，设置中调）/ 日历 60min 轮询（integrations spec）
    private func startPolling() {
        pollingTasks.append(Task { @MainActor [weak self] in
            // 首轮静默由 jiraBaselineSynced 统一管理（成功同步才建立基线）
            while !Task.isCancelled {
                await self?.syncJira(notify: true)
                // 每轮重读设置，改完下个周期生效；下限 5s（演示「现场分配」用，常规建议 ≥30s）
                let interval = max(5, self?.store.settings.jiraPollSeconds ?? 60)
                try? await Task.sleep(for: .seconds(interval))
            }
        })
        // Layer 2: 定时兜底（15min），兜住 EKEventStoreChanged 通知丢失的边角
        pollingTasks.append(Task { @MainActor [weak self] in
            // GitHub PR 轮询：与 Jira 同款（基线静默 + 间隔共用）
            while !Task.isCancelled {
                await self?.syncGitHub(notify: true)
                let interval = max(5, self?.store.settings.jiraPollSeconds ?? 60)
                try? await Task.sleep(for: .seconds(interval))
            }
        })
        pollingTasks.append(Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshCalendarMeetings()
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        })
        // 晚报：每分钟检查是否到点（reminders/ai-pipeline spec）
        pollingTasks.append(Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.maybeShowEveningReport()
                try? await Task.sleep(for: .seconds(60))
            }
        })
    }

    // MARK: - 晨报 / 晚报

    private var todayKey: String {
        Date().formatted(.iso8601.year().month().day())
    }

    private func maybeShowMorningReport() {
        let key = "morningShown-\(todayKey)"
        guard Calendar.current.component(.hour, from: Date()) >= 8,
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2)) // 等面板就位
            let text = (try? await currentAIService().generateMorningReport(store.reportContext)) ?? ""
            store.present(.morningReport(text: text))
        }
    }

    private func maybeShowEveningReport() {
        let now = Date()
        let key = "eveningShown-\(todayKey)"
        guard Calendar.current.component(.hour, from: now) == store.settings.eveningReportHour,
              !UserDefaults.standard.bool(forKey: key) else { return }
        // 不抢占展开态/卡片态：标记不消耗，下一分钟轮询再试（review-fixes #11）
        guard store.islandState.isCompact else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task { @MainActor in
            let text = (try? await currentAIService().generateEveningReport(store.reportContext)) ?? ""
            store.present(.eveningReport(text: text))
        }
    }

    /// 连续清空天数（UserDefaults 简易实现）
    private func bumpClearStreak() -> Int {
        let defaults = UserDefaults.standard
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            .formatted(.iso8601.year().month().day())
        let last = defaults.string(forKey: "lastClearDay")
        var streak = defaults.integer(forKey: "clearStreak")
        if last == todayKey { return max(streak, 1) }
        streak = (last == yesterday) ? streak + 1 : 1
        defaults.set(streak, forKey: "clearStreak")
        defaults.set(todayKey, forKey: "lastClearDay")
        return streak
    }

    // MARK: - 菜单栏

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "TodoIsland"
            )
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "显示/隐藏面板", action: #selector(togglePanel), keyEquivalent: "t")
        menu.addItem(withTitle: "截图 → Todo（F2）", action: #selector(captureTodo), keyEquivalent: "")
        menu.addItem(withTitle: "截图收藏（F3）", action: #selector(captureFavorite), keyEquivalent: "")
        menu.addItem(withTitle: "快速新建 Todo", action: #selector(quickNew), keyEquivalent: "n")
        menu.addItem(.separator())
        menu.addItem(buildDebugMenu())
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 TodoIsland", action: #selector(quitApp), keyEquivalent: "q")
        item.menu = menu

        self.statusItem = item
    }

    /// 面板里的 Debug 入口（PanelTabBar 瓢虫按钮）：菜单栏图标可能被刘海吞掉，
    /// 这里在鼠标位置直接弹同一份 Debug 菜单
    func showDebugMenuAtMouse() {
        guard let menu = buildDebugMenu().submenu else { return }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Debug 状态菜单：联调 + Demo 翻车兜底（island-shell spec）
    private func buildDebugMenu() -> NSMenuItem {
        let debugMenu = NSMenu()
        let entries: [(String, Selector)] = [
            ("任务降落卡（模拟 F2 单任务）", #selector(debugNewTask)),
            ("批量识别（模拟会议纪要）", #selector(debugBatch)),
            ("到期提醒卡", #selector(debugReminder)),
            ("悬停预览", #selector(debugHover)),
            ("展开 Today", #selector(debugToday)),
            ("设置面板", #selector(debugSettings)),
            ("AI 晨报", #selector(debugMorning)),
            ("每日晚报", #selector(debugEvening)),
            ("完成一条（撒花）", #selector(debugCompleteOne)),
            ("全屏庆祝", #selector(debugCelebrate)),
            ("模拟 Jira 新分配", #selector(debugJiraAssign)),
            ("模拟 PR 新分配", #selector(debugPRAssign)),
            ("回到收缩态", #selector(debugDismiss)),
            ("重置演示数据", #selector(debugReset)),
        ]
        for (title, sel) in entries {
            let item = debugMenu.addItem(withTitle: title, action: sel, keyEquivalent: "")
            // 从面板 popUp 时不走菜单栏的响应链，必须显式指 target
            item.target = self
        }
        let item = NSMenuItem(title: "Debug 状态", action: nil, keyEquivalent: "")
        item.submenu = debugMenu
        return item
    }

    // MARK: - 刘海面板

    private func showPanel() {
        guard let screen = NSScreen.main else { return }

        let notchSize = NotchGeometry.notchSize(on: screen)
        // 窗口要装下最大展开态(460×540) + glow 溢光边距
        let panelSize = CGSize(width: 680, height: 660)
        let panelFrame = NotchGeometry.panelFrame(on: screen, panelSize: panelSize)

        let panel = NotchPanel(contentRect: panelFrame)
        let root = IslandRootView(
            notchSize: notchSize,
            onParse: { [weak self] text in
                try? await self?.currentAIService().parseQuickInput(text)
            }
        )
        .environmentObject(store)

        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = hostingView

        panel.setFrame(panelFrame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        guard let panel else { return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    @objc private func captureTodo() { captureService.captureForTodo() }
    @objc private func captureFavorite() { captureService.captureForFavorite() }
    @objc private func quickNew() { store.present(.quickInput) }

    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: - Debug actions

    /// 走完整 AI 链路（含流光），用 Mock 数据
    /// 优先用真实任务数据预览降落卡（没有未完成个人任务才回退 Mock 草稿）
    @objc private func debugNewTask() {
        if let todo = store.personalTodos.first {
            store.present(.newTask(draft: Self.draftFrom(todo)))
            return
        }
        Task { @MainActor in
            let drafts = (try? await mockAIService.parseScreenshot(Data())) ?? []
            if let first = drafts.first { store.present(.newTask(draft: first)) }
        }
    }

    /// 优先用真实任务数据预览批量卡（不足 3 条才回退 Mock 会议纪要）
    @objc private func debugBatch() {
        let real = store.personalTodos.prefix(5).map { Self.draftFrom($0) }
        if real.count >= 3 {
            store.present(.batch(drafts: Array(real)))
            return
        }
        Task { @MainActor in
            let mock = MockAIService()
            mock.batchMode = true
            let drafts = (try? await mock.parseScreenshot(Data())) ?? []
            store.present(.batch(drafts: drafts))
        }
    }

    /// 真实 Todo → 调试预览草稿（保留优先级/截止/周期标签）
    private static func draftFrom(_ todo: Todo) -> TodoDraft {
        TodoDraft(
            title: todo.title,
            source: todo.source,
            priority: todo.priority,
            dueDate: todo.dueDate,
            aiExplanation: "Debug 预览 · 取自当前真实任务",
            tags: todo.tags
        )
    }

    @objc private func debugReminder() {
        let todo = store.pendingTodos.first { $0.dueDate != nil } ?? store.pendingTodos.first
        guard let todo else { return }
        store.present(.reminder(todo: todo))
    }

    @objc private func debugHover() { store.present(.hoverPreview) }
    @objc private func debugToday() { store.present(.expanded(tab: .today)) }
    @objc private func debugSettings() { store.present(.expanded(tab: .settings)) }

    @objc private func debugMorning() {
        Task { @MainActor in
            let text = (try? await currentAIService().generateMorningReport(store.reportContext)) ?? ""
            store.present(.morningReport(text: text))
        }
    }

    @objc private func debugEvening() {
        Task { @MainActor in
            let text = (try? await currentAIService().generateEveningReport(store.reportContext)) ?? ""
            store.present(.eveningReport(text: text))
        }
    }

    @objc private func debugCompleteOne() {
        if let todo = store.pendingTodos.first { store.complete(todo) }
    }

    @objc private func debugCelebrate() {
        // 用真实的连续清空天数（只读不递增），没有记录按 1 天展示
        let streak = max(UserDefaults.standard.integer(forKey: "clearStreak"), 1)
        CelebrationWindowController.shared.celebrate(streakDays: streak)
    }

    /// 走 Mock 演示「现场分配」，不依赖真实 Jira 配置
    @objc private func debugJiraAssign() {
        mockJiraService.extraTicketArmed = true
        Task { @MainActor in
            if let tickets = try? await mockJiraService.fetchAssignedTickets() {
                // prune: false —— Mock 注入不能把真实 ticket 清掉（jira-sync-prune spec）
                store.mergeJiraTodos(tickets, prune: false)
            }
        }
    }

    /// 走 Mock 演示「现场请求 review」，不依赖真实 GitHub 配置
    @objc private func debugPRAssign() {
        mockGitHubService.extraPRArmed = true
        Task { @MainActor in
            if let prs = try? await mockGitHubService.fetchMyPullRequests() {
                // prune: false —— Mock 注入不能把真实 PR 清掉
                store.mergeExternalTodos(prs, source: .github, notify: true, prune: false)
            }
        }
    }

    @objc private func debugDismiss() { store.dismiss() }
    @objc private func debugReset() { store.resetDemoData() }
}
