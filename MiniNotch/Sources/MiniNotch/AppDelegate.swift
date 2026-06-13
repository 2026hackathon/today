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
    /// Mock 常驻：邮件未配置时兜底演示 + Debug「模拟新邮件」演示
    private let mockEmailService = MockEmailService()
    /// EventKit 真实日历服务（权限就绪时使用；被拒/失败 → 上层按空列表处理，不用 Mock 填充）
    private let eventKitCalendarService = EventKitCalendarService()
    private lazy var reminderScheduler: ReminderScheduler = TimerReminderScheduler()
    private lazy var pushService: PushService = NoopPushService()     // 到期提醒走系统通知中心
    /// coding agent 会话监控（agent-session spec，借鉴 Vibe Island）
    private let agentService = AgentSessionService()

    /// 外部源同步基线：首次「成功」同步后置位，之后的新 key 才弹通知卡。
    /// 失败不置位（review-fixes #2：否则首轮断网 → 第二轮全量误报为新分配）
    private var jiraBaselineSynced = false
    private var githubBaselineSynced = false
    /// 未配置时的清空只在启动后第一次同步执行（清历史 Mock/旧数据）；
    /// 运行期未配置多半是用户正在设置页编辑凭证，跳过同步避免 prune
    /// 误删真实数据（review-fixes #1）
    private var didLaunchCleanupJira = false
    private var didLaunchCleanupGitHub = false
    /// 邮件首轮同步静默基线（首轮不弹降落卡，避免初始全量误报为新消息）
    private var emailBaselineSynced = false

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
        setupAgentMonitor()
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
        // 看截图大图（盖在岛上层的模态）期间不收起，关闭查看器后恢复
        guard store.islandState.isDismissable, !store.screenshotViewerOpen else { return }
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
                // newTask/batch 也要激活：卡里的优先级/时间/提前提醒是 SwiftUI Menu，
                // 非激活的 accessory 面板里 Menu 标签不渲染（显示成空白），激活后才画出来
                let needsKeyboard: Bool = switch state {
                case .quickInput, .editTask, .newTask, .batch, .expanded(tab: .settings): true
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
        captureService.onTodoCapture = { [weak self] images, paths in
            guard let self else { return }
            self.store.isAIWorking = true
            Task { @MainActor in
                do {
                    var drafts = try await self.currentAIService().parseScreenshots(images)
                    for i in drafts.indices { drafts[i].screenshotPaths = paths }
                    self.store.isAIWorking = false
                    if drafts.count >= 3 {
                        self.store.present(.batch(drafts: drafts))
                    } else if let first = drafts.first {
                        self.store.present(.newTask(draft: first))
                    } else {
                        // 没识别到 → 手动录入兜底，给出明确提示
                        self.store.quickInputNotice = "截图里未识别到待办，可手动录入"
                        self.store.present(.quickInput)
                    }
                } catch {
                    AIDebugLog.record("截图解析抛错：\(error)")
                    self.store.isAIWorking = false
                    if case AIServiceError.notConfigured = error {
                        self.store.quickInputNotice = "未配置 AI，无法解析截图。请在设置填入 API Key，或手动录入"
                    } else {
                        self.store.quickInputNotice = "AI 解析失败（网络/Key 问题），可手动录入"
                    }
                    self.store.present(.quickInput)
                }
            }
        }
        // F3 收藏：文件已落盘 favorites/，收藏 Tab 待接入（capture spec / owner C）
        captureService.onFavoriteCapture = { path in
            NSLog("[Capture] favorited: \(path)") // TODO(C): 收藏 Tab + AI 打标签
        }
        // 缺「屏幕录制」权限：弹快速录入给出明确提示，并打开系统设置对应面板（授权后需重启 App）
        captureService.onScreenRecordingDenied = { [weak self] in
            guard let self else { return }
            self.store.isAIWorking = false
            self.store.quickInputNotice = "截图需要「屏幕录制」权限：请在 系统设置 › 隐私与安全性 › 屏幕录制 里勾选本应用，授权后重启生效。可先手动录入"
            self.store.present(.quickInput)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        captureService.start()
        // 全局热键按 settings 注册，改键即热生效（Published 首发当前值 → 同时完成首次注册）。
        // removeDuplicates 避免无关设置变更（如输入 Jira token）反复重注册热键。
        store.$settings
            .map { [$0.todoHotKey, $0.favoriteHotKey, $0.voiceHotKey] }
            .removeDuplicates()
            .sink { [weak self] keys in
                self?.captureService.applyHotKeys(todo: keys[0], favorite: keys[1], voice: keys[2])
            }
            .store(in: &cancellables)

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
                // 声音只在到期时刻播一次（F-04：到期=声音；过期级 5min 重复一次，
                // 循环响铃太吵故不播）。勿扰时段 scheduler 不触发，无需再判
                if level == .due {
                    NSSound(named: "Glass")?.play()
                }
                Task { await self.pushService.push(title: "⏰ 任务到期", body: todo.title) }
            case .oneHour, .fifteenMin:
                self.store.refreshCompactState()
                // 提前 15min 档「震动」：触控板触觉反馈一次
                // （F-04：中=橙色脉冲+震动；无 Force Touch 设备自动无感）
                if level == .fifteenMin {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
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
            await self?.syncEmail(notify: true)
            self?.refreshAISuggestion()
        }

        // 剪贴板贴图识别：找到图走 AI 管线；没图就引导手动录入（与「未识别」兜底一致）
        store.onPasteScreenshot = { [weak self] in
            guard let self else { return }
            if !self.captureService.captureFromPasteboard() {
                self.store.quickInputNotice = "剪贴板里没有图片，先用截图工具复制，或手动录入"
                self.store.present(.quickInput)
            }
        }

        // 快速录入框 ⌘V 贴图后回车：拿到 PNG（可多张）直接走与截图相同的识别流水线
        store.onRecognizeImages = { [weak self] pngs in
            self?.captureService.recognize(pngDataList: pngs)
        }

        // ⌥Space 全局语音速记：弹快速录入并自动开始聆听
        captureService.onVoiceCapture = { [weak self] in
            self?.store.presentVoiceInput()
        }

        // 提醒事项任务完成/撤销 → EventKit 回写（失败仅记日志，本地状态不回滚）
        store.onReminderCompletionChanged = { [weak self] identifier, completed in
            Task { @MainActor in
                guard let service = self?.currentCalendarService() else { return }
                do {
                    try await service.setReminderCompleted(identifier: identifier, completed: completed)
                } catch {
                    NSLog("[Calendar] setReminderCompleted failed: \(error)")
                }
            }
        }

        // 提醒事项 snooze → 新截止时间回写 EventKit（Apple 提醒事项同步）
        store.onReminderSnoozed = { [weak self] identifier, due in
            Task { @MainActor in
                guard let service = self?.currentCalendarService() else { return }
                try? await service.setReminderDue(identifier: identifier, due: due)
            }
        }

        // 删除苹果来源项 → 从 EventKit 真删除对应事件/提醒（失败仅记日志，本地已移除）
        store.onCalendarItemDeleted = { [weak self] identifier in
            Task { @MainActor in
                guard let service = self?.currentCalendarService() else { return }
                do {
                    try await service.deleteCalendarItem(identifier: identifier)
                } catch {
                    NSLog("[Calendar] deleteCalendarItem failed: \(error)")
                }
            }
        }

        // ── 日历三层同步（apple-calendar-integration spec）──
        // Layer 1: 事件驱动（EKEventStoreChanged → 即时刷新）—— 权限授予后才挂接
        // Layer 3: 前台刷新（展开面板时立即拉一次）
        store.$islandState
            .sink { [weak self] newState in
                guard case .expanded(let tab) = newState else { return }
                Task { @MainActor in
                    self?.refreshCalendarMeetings()
                    // 点开日历页签 = 明确意图：权限未决定时直接弹系统授权弹窗
                    if tab == .calendar { self?.promptCalendarAccessIfNeeded() }
                }
            }
            .store(in: &cancellables)

        // 日历面板空态「允许访问日历 / 前往系统设置」按钮
        store.onRequestCalendarAccess = { [weak self] in
            self?.handleCalendarAccessRequest()
        }

        // 磁盘清理：扫描无需凭证（du 只读），分类复用 currentAIService()（无 Key 时回退规则）
        store.diskCleanupServiceProvider = { [weak self] in
            self?.currentDiskCleanupService() ?? RealDiskCleanupService(ai: MockAIService())
        }

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
            workItems: store.activeWorkItems,
            completedToday: store.completedToday,
            meetings: store.todayMeetings
        )
    }

    /// 启动时的日历权限处理：已授权 → 挂监听拉数据；未决定 → 弹系统授权弹窗。
    private func requestCalendarAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        updateCalendarAuthUIState()
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
        promptCalendarAccessDialog()
    }

    /// 弹系统日历授权弹窗（仅 .notDetermined 时系统才会真的弹）。
    /// accessory 应用需临时切 .regular 激活策略，否则系统权限弹窗不显示
    /// （LSUIElement 应用无前台权限）；结束后恢复 accessory。
    private func promptCalendarAccessDialog() {
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
            self.updateCalendarAuthUIState()

            if granted {
                self.wireCalendarLayer1()
                self.performInitialSyncIfNeeded()
                self.refreshCalendarMeetings()
            } else {
                NSLog("[Calendar] permission denied — meetings stay empty (no mock fill)")
            }
        }
    }

    /// 点开日历页签时权限仍未决定 → 主动弹授权弹窗
    private func promptCalendarAccessIfNeeded() {
        updateCalendarAuthUIState()
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        promptCalendarAccessDialog()
    }

    /// 空态按钮动作：未决定 → 弹系统弹窗；被拒 → 系统不允许 App 再弹，打开系统设置日历隐私页
    private func handleCalendarAccessRequest() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            promptCalendarAccessDialog()
        case .fullAccess:
            updateCalendarAuthUIState()
            refreshCalendarMeetings()
        default: // denied / restricted / writeOnly
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        }
    }

    /// 把 EKAuthorizationStatus 映射进 store（CalendarPanel 空态授权引导用）
    private func updateCalendarAuthUIState() {
        let events = EKEventStore.authorizationStatus(for: .event)
        let reminders = EKEventStore.authorizationStatus(for: .reminder)
        let state: AppStore.CalendarAuthUIState
        if events == .fullAccess || reminders == .fullAccess {
            state = .authorized
        } else if events == .notDetermined {
            state = .needsRequest
        } else {
            state = .denied // denied / restricted / writeOnly（writeOnly 读不到日程）
        }
        if store.calendarAuthState != state { store.calendarAuthState = state }
    }

    /// 首次同步检查：如果从未完成过首次同步，执行默认窗口（今天起 7 天）拉取
    private func performInitialSyncIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "calendarInitialSyncCompleted") else { return }
        NSLog("[Calendar] performing initial sync (today + 7-day window)")
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
        await syncMentions()
    }

    /// @我同步：未配置 Atlassian 凭据 → 空（不 Mock 填充列表，同其他源口径）
    private func syncMentions() async {
        guard let service = currentMentionService() else { store.replaceMentions([]); return }
        if let items = try? await service.fetchMentions() {
            store.replaceMentions(items)
        }
    }

    private func currentMentionService() -> MentionService? {
        let s = store.settings
        guard !s.jiraBaseURL.isEmpty, !s.jiraEmail.isEmpty, !s.jiraAPIToken.isEmpty else { return nil }
        return RealMentionService(baseURL: s.jiraBaseURL, email: s.jiraEmail, apiToken: s.jiraAPIToken)
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

    /// 磁盘清理：始终走 Real（du 扫描无需凭证）。分类用 currentAIService()——
    /// 无 Key 时它是 Mock，分类调用抛错 → RealDiskCleanupService 回退规则并提示。
    private func currentDiskCleanupService() -> DiskCleanupService {
        RealDiskCleanupService(ai: currentAIService())
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

    /// 邮件装配（integrations spec）：可同时接入多个来源——O365(Graph) + Gmail(IMAP XOAUTH2)
    /// + 其它 IMAP(应用密码)。都未配置时回退 Mock（无凭证也能演示）。
    private func currentEmailServices() -> [EmailService] {
        var services: [EmailService] = []
        // O365：已用 Microsoft 登录 → Graph（/me/messages），不依赖 IMAP 主机/开关
        if MicrosoftOAuth.shared.isSignedIn {
            services.append(GraphEmailService())
        }
        // Gmail：已用 Google 登录 → imap.gmail.com + XOAUTH2
        if GoogleOAuth.shared.isSignedIn, !GoogleOAuth.shared.accountEmail.isEmpty {
            let email = GoogleOAuth.shared.accountEmail
            services.append(RealEmailService(host: "imap.gmail.com", email: email,
                                             auth: .oauth { try await GoogleOAuth.shared.validAccessToken() }))
        }
        // ── 手动「IMAP + 应用密码」兜底通道暂停用（当前用不上；OAuth 已覆盖 O365/Gmail）──
        // 恢复时取消注释下段，并恢复 SettingsPanel 的 IMAP 字段与测试连接对应段。
        // Gmail OAuth 不走这里（它用上面的 imap.gmail.com + XOAUTH2，独立于这些设置字段）。
        // let s = store.settings
        // let password = store.emailAppPassword   // Keychain
        // if !s.emailImapHost.isEmpty, !s.emailAddress.isEmpty, !password.isEmpty,
        //    !Self.isOffice365IMAP(s.emailImapHost) {
        //     services.append(RealEmailService(host: s.emailImapHost, email: s.emailAddress, auth: .password(password)))
        // }
        // 未连接任何邮箱 → 返回空，不再用 Mock 假数据填充消息页（用户要求去掉 mock）。
        // MockEmailService 仍保留，只供 Debug 菜单「模拟新邮件」显式演示。
        return services
    }

    /// O365 IMAP 主机 —— 基础认证已被禁用，密码 IMAP 必失败，应跳过（走 Microsoft 登录/Graph）。
    /// 手动 IMAP 通道恢复时复用此判断。
    static func isOffice365IMAP(_ host: String) -> Bool {
        host.lowercased().contains("office365.com")
    }

    /// 拉取一轮邮件：多来源各自 fetch（来源识别/链接归一/隐私预处理在服务层完成），
    /// 跨来源按 messageId 去重，再调 AI 分析重要级别 + ≤20 字一句话建议入库。
    /// 去重在 AI 之前（避免对已知邮件重复打 LLM）；首轮静默不弹卡。
    private func syncEmail(notify: Bool, services: [EmailService]? = nil) async {
        var inputs: [EmailDigestInput] = []
        for service in (services ?? currentEmailServices()) {
            if let got = try? await service.fetchNewMessages() { inputs.append(contentsOf: got) }
        }
        guard !inputs.isEmpty else { return }
        let knownIds = Set(store.messages.map(\.messageId))
        var seen = Set<String>()
        let fresh = inputs.filter { !knownIds.contains($0.messageId) && seen.insert($0.messageId).inserted }
        guard !fresh.isEmpty else { emailBaselineSynced = true; return }
        // AI 分析；无 Key/失败时 AIService 自身已降级，这里再兜一层规则化
        let analyses = (try? await currentAIService().analyzeEmails(fresh))
            ?? fresh.map { EmailAnalysis(importance: EmailHeuristics.importance($0),
                                         suggestion: EmailSummary.suggestion($0)) }
        let messages = zip(fresh, analyses).map { input, a in
            Message(messageId: input.messageId, summary: a.suggestion, source: input.source,
                    importance: a.importance, link: input.link, receivedAt: input.receivedAt,
                    sender: input.sender, rawSubject: input.subject)
        }
        store.addMessages(messages, notify: notify && emailBaselineSynced)
        emailBaselineSynced = true
    }

    /// 拉取一轮 Jira：未配置时合并空列表（prune 清掉历史 Mock/失效残留）
    private func syncJira(notify: Bool) async {
        guard let service = currentJiraService() else {
            if !didLaunchCleanupJira {
                didLaunchCleanupJira = true
                store.mergeJiraWorkItems([], notify: false)
            }
            return // 运行期未配置（编辑凭证窗口）：跳过，不 prune
        }
        didLaunchCleanupJira = true
        if let tickets = try? await service.fetchAssignedTickets() {
            store.mergeJiraWorkItems(tickets, notify: notify && jiraBaselineSynced)
            jiraBaselineSynced = true
        }
    }

    /// 拉取一轮 GitHub PR：未配置时合并空列表（prune 清残留）
    private func syncGitHub(notify: Bool) async {
        guard let service = currentGitHubService() else {
            if !didLaunchCleanupGitHub {
                didLaunchCleanupGitHub = true
                store.mergeWorkItems([], source: .github, notify: false)
            }
            return // 运行期未配置：跳过，不 prune（review-fixes #1）
        }
        didLaunchCleanupGitHub = true
        if let prs = try? await service.fetchMyPullRequests() {
            store.mergeWorkItems(prs, source: .github, notify: notify && githubBaselineSynced)
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
        // 邮件轮询：与 Jira 同款间隔（首轮由 emailBaselineSynced 静默）
        pollingTasks.append(Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.syncEmail(notify: true)
                let interval = max(5, self?.store.settings.jiraPollSeconds ?? 60)
                try? await Task.sleep(for: .seconds(interval))
            }
        })
        // @我提及：5min 轮询（变动不频繁，不必跟 Jira 同频）
        pollingTasks.append(Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.syncMentions()
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        })
        // 晚报每分钟检查是否到点（reminders/ai-pipeline spec）+ agent 陈旧会话清理
        pollingTasks.append(Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.maybeShowEveningReport()
                self?.store.sweepStaleAgentSessions()
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
        menu.addItem(withTitle: "从剪贴板识别截图", action: #selector(pasteCapture), keyEquivalent: "v")
        menu.addItem(withTitle: "语音速记（⌥Space）", action: #selector(voiceCapture), keyEquivalent: "")
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
            ("glow①提前（橙慢呼吸 near）", #selector(debugGlowNear)),
            ("glow②临近（橙脉冲 urgent）", #selector(debugGlowWarning)),
            ("glow④过期（红强脉冲）", #selector(debugGlowOverdue)),
            ("glow·AI 解析（彩虹流光 3s）", #selector(debugGlowAI)),
            ("悬停预览", #selector(debugHover)),
            ("展开 Today", #selector(debugToday)),
            ("设置面板", #selector(debugSettings)),
            ("AI 晨报", #selector(debugMorning)),
            ("每日晚报", #selector(debugEvening)),
            ("完成一条（撒花）", #selector(debugCompleteOne)),
            ("全屏庆祝", #selector(debugCelebrate)),
            ("模拟 Jira 新分配", #selector(debugJiraAssign)),
            ("模拟 PR 新分配", #selector(debugPRAssign)),
            ("模拟 Agent 运行中", #selector(debugAgentWorking)),
            ("模拟 Agent 等待确认", #selector(debugAgentWaiting)),
            ("模拟 Agent 完成（弹卡）", #selector(debugAgentDone)),
            ("清空 Agent 会话", #selector(debugAgentClear)),
            ("安装 Claude Code Hook", #selector(debugInstallAgentHook)),
            ("安装 opencode 插件", #selector(debugInstallOpenCodePlugin)),
            ("模拟新邮件", #selector(debugNewMail)),
            ("打开 AI 调试日志", #selector(debugOpenAILog)),
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

    // MARK: - Agent 会话监控（agent-session spec）

    private func setupAgentMonitor() {
        agentService.onEvent = { [weak self] event in
            self?.store.applyAgentEvent(event)
        }
        // agent 一轮完成 → 轻提示音 + 完成通知卡（agent-landed-jump spec）
        store.onAgentReplied = { [weak self] session in
            guard let self else { return }
            if self.store.settings.effectsEnabled, let sound = NSSound(named: "Glass") {
                sound.volume = 0.5
                sound.play()
            }
            // 完成即弹降落卡（与 jira/新消息一致）：收缩态就弹，倒计时自动收回。
            // 不再做「盯着终端就不弹」的抑制——那会让最常见的「在该终端跑完」场景看不到卡。
            if self.store.islandState.isCompact {
                self.store.present(.agentLanded(session: session))
            }
        }
        // Agent 面板/卡片点击跳转
        store.onAgentJump = { [weak self] session in
            self?.agentService.jumpTo(session)
        }
        agentService.start()
    }

    // MARK: - 刘海面板

    private func showPanel() {
        guard let screen = NSScreen.main else { return }

        let notchSize = NotchGeometry.notchSize(on: screen)
        // 窗口要装下最大展开态(460×540) + glow 溢光边距
        let panelSize = CGSize(width: 680, height: 660)
        let panelFrame = NotchGeometry.panelFrame(on: screen, panelSize: panelSize)

        let panel = NotchPanel(contentRect: panelFrame)
        // 命中区域：岛体之外的透明区放行点击穿透到下方应用（island-shell spec）
        let hitRegion = IslandHitRegion()
        let root = IslandRootView(
            notchSize: notchSize,
            onParse: { [weak self] text in
                try? await self?.currentAIService().parseQuickInput(text)
            },
            onJumpToAgent: { [weak self] session in
                self?.agentService.jumpTo(session)
            },
            hitRegion: hitRegion
        )
        .environmentObject(store)

        let hostingView = PassthroughHostingView(rootView: root, hitRegion: hitRegion)
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
    @objc private func pasteCapture() { store.pasteScreenshot() }
    @objc private func voiceCapture() { store.presentVoiceInput() }
    @objc private func captureFavorite() { captureService.captureForFavorite() }
    @objc private func quickNew() {
        store.quickInputNotice = nil
        store.present(.quickInput)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: - Debug actions

    /// 走完整 AI 链路（含流光），用 Mock 数据
    /// 优先用真实任务数据预览降落卡（没有未完成个人任务才回退 Mock 草稿）
    @objc private func debugNewTask() {
        if let todo = store.personalTodos.first {
            store.present(.newTask(draft: Self.draftFrom(todo)))
            return
        }
        store.present(.newTask(draft: MockAIService.demoScreenshotDraft()))
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
            let drafts = (try? await mock.parseScreenshots([Data()])) ?? []
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

    // MARK: Debug —— glow 分档预览（直接置 compact 态看发光，数据变化后自动回落）
    @objc private func debugGlowNear() {
        store.debugForceRedGlow = false
        store.present(.near)
    }
    @objc private func debugGlowWarning() {
        store.debugForceRedGlow = false
        store.present(.urgent)   // 无超期 → 橙色 warning 脉冲
    }
    @objc private func debugGlowOverdue() {
        store.debugForceRedGlow = true
        store.present(.urgent)   // 强制走红色 urgent 脉冲
    }
    @objc private func debugGlowAI() {
        store.present(.aiWorking)            // 彩虹流光
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.store.debugForceRedGlow = false
            self?.store.dismiss()
        }
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
                store.mergeJiraWorkItems(tickets, prune: false)
            }
        }
    }

    /// 走 Mock 演示「现场请求 review」，不依赖真实 GitHub 配置
    @objc private func debugPRAssign() {
        mockGitHubService.extraPRArmed = true
        Task { @MainActor in
            if let prs = try? await mockGitHubService.fetchMyPullRequests() {
                // prune: false —— Mock 注入不能把真实 PR 清掉
                store.mergeWorkItems(prs, source: .github, notify: true, prune: false)
            }
        }
    }

    @objc private func debugAgentWorking() {
        store.debugUpsertAgentSession(id: "demo-\(store.agentSessions.count + 1)", state: .working, project: "today")
    }

    @objc private func debugAgentWaiting() {
        store.debugUpsertAgentSession(
            id: "demo-wait-\(store.waitingAgentCount + 1)", state: .waiting,
            project: "today", message: "需要权限运行 Bash"
        )
    }

    @objc private func debugAgentDone() {
        // 先标记运行中再转完成，触发 onAgentReplied → 弹完成卡
        let id = "demo-done-\(store.agentSessions.count + 1)"
        store.debugUpsertAgentSession(id: id, state: .working, project: "today")
        store.debugUpsertAgentSession(id: id, state: .replied, project: "today")
    }

    @objc private func debugAgentClear() { store.clearAgentSessions() }

    @objc private func debugInstallAgentHook() {
        let msg = agentService.installClaudeCodeHook()
        NSLog("[Agent] \(msg)")
    }

    @objc private func debugInstallOpenCodePlugin() {
        let msg = agentService.installOpenCodePlugin()
        NSLog("[Agent] \(msg)")
    }

    /// 走 Mock 演示「现场来信」：额外注入 1 封新邮件，弹消息降落卡
    @objc private func debugNewMail() {
        mockEmailService.extraMailArmed = true
        Task { @MainActor in
            // 演示需弹卡：先确保已过首轮静默基线。Mock 不再是默认来源，显式传入。
            emailBaselineSynced = true
            await syncEmail(notify: true, services: [mockEmailService])
        }
    }

    /// 打开 AI 调试日志（识图/解析失败原因；不存在则先建空文件再打开）
    @objc private func debugOpenAILog() {
        let url = AIDebugLog.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "（暂无 AI 调试记录）\n".data(using: .utf8)?.write(to: url)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func debugDismiss() { store.dismiss() }
    @objc private func debugReset() { store.resetDemoData() }
}
