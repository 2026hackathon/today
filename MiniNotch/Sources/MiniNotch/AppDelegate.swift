import AppKit
import Combine
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

    private lazy var aiService: AIService = MockAIService()           // owner B: 换 AnthropicAIService(apiKey:)
    private lazy var captureService: CaptureService = HotkeyCaptureService() // owner C
    /// Mock 常驻：配置不全时兜底 + Debug「模拟 Jira 新分配」演示
    private let mockJiraService = MockJiraService()
    private lazy var calendarService: CalendarService = MockCalendarService() // owner C: 换 EventKitCalendarService()
    private lazy var reminderScheduler: ReminderScheduler = TimerReminderScheduler()
    private lazy var pushService: PushService = NoopPushService()     // owner C: 按 settings 换 Feishu/Bark

    private var cancellables = Set<AnyCancellable>()
    private var pollingTasks: [Task<Void, Never>] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory 模式：不占 Dock、不出现在 ⌘Tab 切换里
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()
        showPanel()
        wireServices()
        startPolling()
        maybeShowMorningReport()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTasks.forEach { $0.cancel() }
    }

    // MARK: - 服务装配

    private func wireServices() {
        // F2 截图 → AI 解析 → 任务降落 / 批量识别（ai-pipeline spec）
        captureService.onTodoCapture = { [weak self] data, path in
            guard let self else { return }
            self.store.isAIWorking = true
            Task { @MainActor in
                do {
                    var drafts = try await self.aiService.parseScreenshot(data)
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
                self.store.present(.reminder(todo: todo))
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

        // 完成今日全部 → 全屏庆祝（effects spec）
        store.onCompletedAll = { [weak self] in
            guard let self, self.store.settings.effectsEnabled else { return }
            CelebrationWindowController.shared.celebrate(streakDays: self.bumpClearStreak())
        }
    }

    /// 按配置动态选择 Jira 服务：三项齐全 → Real，否则 → Mock。
    /// 每个轮询周期重新判定，设置面板改完即生效，无需重启（integrations spec delta）。
    private func currentJiraService() -> JiraService {
        let s = store.settings
        if !s.jiraBaseURL.isEmpty, !s.jiraEmail.isEmpty, !s.jiraAPIToken.isEmpty {
            return RealJiraService(baseURL: s.jiraBaseURL, email: s.jiraEmail, apiToken: s.jiraAPIToken)
        }
        return mockJiraService
    }

    /// Jira 60s / 日历 60min 轮询（integrations spec）
    private func startPolling() {
        pollingTasks.append(Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, let tickets = try? await self.currentJiraService().fetchAssignedTickets() {
                    self.store.mergeJiraTodos(tickets)
                }
                try? await Task.sleep(for: .seconds(60))
            }
        })
        pollingTasks.append(Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, let meetings = try? await self.calendarService.fetchTodayMeetings() {
                    self.store.replaceMeetings(meetings)
                }
                try? await Task.sleep(for: .seconds(60 * 60))
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
            let text = (try? await aiService.generateMorningReport(store.reportContext)) ?? ""
            store.present(.morningReport(text: text))
        }
    }

    private func maybeShowEveningReport() {
        let now = Date()
        let key = "eveningShown-\(todayKey)"
        guard Calendar.current.component(.hour, from: now) == store.settings.eveningReportHour,
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task { @MainActor in
            let text = (try? await aiService.generateEveningReport(store.reportContext)) ?? ""
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
            ("回到收缩态", #selector(debugDismiss)),
            ("重置演示数据", #selector(debugReset)),
        ]
        for (title, sel) in entries {
            debugMenu.addItem(withTitle: title, action: sel, keyEquivalent: "")
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
                try? await self?.aiService.parseQuickInput(text)
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
    @objc private func debugNewTask() {
        store.isAIWorking = true
        Task { @MainActor in
            let mock = MockAIService()
            let drafts = (try? await mock.parseScreenshot(Data())) ?? []
            store.isAIWorking = false
            if let first = drafts.first { store.present(.newTask(draft: first)) }
        }
    }

    @objc private func debugBatch() {
        store.isAIWorking = true
        Task { @MainActor in
            let mock = MockAIService()
            mock.batchMode = true
            let drafts = (try? await mock.parseScreenshot(Data())) ?? []
            store.isAIWorking = false
            store.present(.batch(drafts: drafts))
        }
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
            let text = (try? await aiService.generateMorningReport(store.reportContext)) ?? ""
            store.present(.morningReport(text: text))
        }
    }

    @objc private func debugEvening() {
        Task { @MainActor in
            let text = (try? await aiService.generateEveningReport(store.reportContext)) ?? ""
            store.present(.eveningReport(text: text))
        }
    }

    @objc private func debugCompleteOne() {
        if let todo = store.pendingTodos.first { store.complete(todo) }
    }

    @objc private func debugCelebrate() {
        CelebrationWindowController.shared.celebrate(streakDays: 3)
    }

    /// 走 Mock 演示「现场分配」，不依赖真实 Jira 配置
    @objc private func debugJiraAssign() {
        mockJiraService.extraTicketArmed = true
        Task { @MainActor in
            if let tickets = try? await mockJiraService.fetchAssignedTickets() {
                store.mergeJiraTodos(tickets)
            }
        }
    }

    @objc private func debugDismiss() { store.dismiss() }
    @objc private func debugReset() { store.resetDemoData() }
}
