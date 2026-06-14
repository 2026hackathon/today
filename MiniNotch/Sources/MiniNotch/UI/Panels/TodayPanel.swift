import AppKit
import SwiftUI

// ============================================================
// TodayPanel —— 展开态主面板（today-focus-redesign）。
// Today 只回答「我今天要关注什么」，按时间相关性组织：
//   已超期 → 今日任务（有时间 → 无固定时间，含当天日程/提醒）→ 已完成
// 来源（截图/Jira/日历/提醒事项…）退化为行内小图标，不再作为分组依据。
// 非今日内容在 Inbox tab（InboxPanel.swift）。
// 本文件同时提供 Panels 模块的公共小组件（PanelTabBar / PanelSectionTitle /
// PanelDivider / PanelAISuggestion / PanelPriorityTag / PanelFormat / 行组件）。
// ============================================================

struct TodayPanel: View {
    @EnvironmentObject var store: AppStore
    @State private var showCompleted = false

    private var currentTab: PanelTab {
        if case .expanded(let tab) = store.islandState { return tab }
        return .today
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelTabBar(current: currentTab)
            PanelScrollView {
                switch currentTab {
                case .messages:
                    InboxHubPanel()   // 邮件消息 + @我提及，内部分段切换
                case .workItems:
                    WorkItemPanel()   // 全部 Jira/GitHub 工作项
                case .agent:
                    AgentPanel()
                default:
                    todayBody
                }
            }
            
        }
        .padding(.top, 36) // 摄像头区留位（prototype .island-body）
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Today 内容

    private var greeting: String {
        var parts = ["今天 \(store.todayFocusCount) 个任务"]
        // 只算真实会议(排除提醒事项——它们以 .calendar 任务计入「任务」)且未完成的，
        // 否则已完成的提醒会被错当成「N 场会议」显示，列表里却看不到
        let meetingCount = store.todayMeetings.filter { !$0.isReminder && !store.isMeetingCompleted($0) }.count
        if meetingCount > 0 { parts.append("\(meetingCount) 场会议") }
        if !store.overdueTodos.isEmpty { parts.append("\(store.overdueTodos.count) 项超期") }
        return parts.joined(separator: "、")
    }

    private var todayBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 问候行
            Text(greeting)
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 10)

            // AI 建议条置顶：先看建议再看清单（任务/会议变化后自动重新生成）
            PanelAISuggestion(text: store.aiSuggestion)
                .padding(.bottom, 12)

            // 1. 已超期（红色高亮，空则隐藏）
            if !store.overdueTodos.isEmpty {
                PanelSectionTitle(title: "已超期", count: store.overdueTodos.count, color: DS.Colors.alert)
                ForEach(store.overdueTodos) { todo in
                    TaskRow(todo: todo)
                }
                PanelDivider()
            }

            // 2. 今日任务：有时间按时间排 → 细分隔线 → 无固定时间按优先级排
            PanelSectionTitle(
                title: "今日任务",
                count: store.todayTimedTodos.count + store.todayUntimedTodos.count + store.activeWorkItems.count
            )
            if store.todayTimedTodos.isEmpty && store.todayUntimedTodos.isEmpty && store.activeWorkItems.isEmpty {
                Text("今天没有要处理的任务")
                    .font(DS.Fonts.meta)
                    .foregroundStyle(DS.Colors.text3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            // 可点击完成的个人任务置顶：有时间按时间排 → 无时间按优先级排
            ForEach(store.todayTimedTodos) { todo in
                TaskRow(todo: todo)
            }
            if !store.todayUntimedTodos.isEmpty {
                if !store.todayTimedTodos.isEmpty {
                    PanelMiniDividerLabel(text: "无固定时间")
                }
                ForEach(store.todayUntimedTodos) { todo in
                    TaskRow(todo: todo)
                }
            }
            // agent 会话栏：只展示需要你处理的（已完成/待确认），运行中的不在 Today 露出
            if !store.attentionAgentSessions.isEmpty {
                PanelMiniDividerLabel(text: "Agent")
                ForEach(store.attentionAgentSessions) { session in
                    AgentSessionRow(session: session, onJump: { store.jumpToAgent(session) })
                }
            }
            // 工作项沉底（Jira/GitHub 只读不可完成，不挡可操作任务）
            if !store.activeWorkItems.isEmpty {
                if !store.todayTimedTodos.isEmpty || !store.todayUntimedTodos.isEmpty
                    || !store.sortedAgentSessions.isEmpty {
                    PanelMiniDividerLabel(text: "工作项")
                }
                ForEach(store.activeWorkItems) { item in
                    WorkItemRow(item: item)
                }
            }

            PanelDivider()

            // 今日日程不再单独成段：当天日程/提醒以 .calendar 任务进入「今日任务」
            // （today-tasks-schedule-reminders spec），完整时间线在日历页签

            completedFold
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 已完成折叠

    private var completedFold: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(IslandAnimation.spring) { showCompleted.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showCompleted ? "▾" : "▸")
                    Text("已完成 (\(store.completedToday.count))")
                }
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
            .padding(.vertical, 6)

            if showCompleted {
                ForEach(store.completedToday) { todo in
                    CompletedRow(todo: todo) { store.uncomplete(todo) }
                }
            }
        }
    }
}

// MARK: - 任务行统一布局度量

/// PersonalTodoRow 与 MeetingRow 共用的行布局度量，保证同一列表内
/// 状态字形、时间轨、标题起始位置像素级对齐（time-first / priority-last）。
enum PanelRowMetric {
    /// HStack 行内间距
    static let spacing: CGFloat = 8
    /// 状态字形列宽（绿勾 / 完成圈 / 小点）
    static let statusGlyphWidth: CGFloat = 16
    /// 时间轨列宽（等宽左对齐，标题对齐到同一竖线）
    /// 56pt 为 snooze 铃铛(8pt)+间距(3pt)+HH:mm 预留，避免时间换行
    static let timeTrackWidth: CGFloat = 56
}

// MARK: - 统一任务行（Todo 现已全是个人来源；外部工单走 WorkItemRow）

struct TaskRow: View {
    let todo: Todo
    @EnvironmentObject var store: AppStore

    var body: some View {
        PersonalTodoRow(todo: todo) { store.complete(todo) }
    }
}

// MARK: - 个人 Todo 行

struct PersonalTodoRow: View {
    let todo: Todo
    let onComplete: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var hovering = false
    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .center, spacing: PanelRowMetric.spacing) {
            // 状态字形：完成绿勾(撤销) / 可完成圈 / 未来静态小点，等宽占位
            statusGlyph
                .frame(width: PanelRowMetric.statusGlyphWidth)

            // 时间轨：行首等宽左对齐，标题对齐到同一竖线；无截止时间留空占位
            timeTrack
                .frame(width: PanelRowMetric.timeTrackWidth, alignment: .leading)

            // 标题：单行，完成态删除线
            Text(todo.title)
                .font(DS.Fonts.todoTitle)
                .foregroundStyle(todo.isCompleted ? DS.Colors.text3 : DS.Colors.text1)
                .strikethrough(todo.isCompleted, color: DS.Colors.text3)
                .lineLimit(1)

            // kind 标签：日程/提醒才显示（纯任务不显，避免噪音）；
            // 苹果日历同步项据此区分「日程」「提醒」
            if todo.kind != .task {
                Text(todo.kind.label)
                    .dsTag(DS.Colors.accent, bg: DS.Colors.accentSoft)
            }
            ForEach(todo.tags, id: \.self) { tag in
                HStack(spacing: 3) {
                    Image(systemName: "repeat").font(.system(size: 8))
                    Text(tag)
                }
                .dsTag()
            }
            // 截图来源且有图：小相机可点，点击用「预览」打开全部原图（多图带数量角标）
            if todo.source == .screenshot, !todo.screenshotPaths.isEmpty {
                Button {
                    ScreenshotViewer.open(todo.screenshotPaths, store: store)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "camera.fill").font(.system(size: 9))
                        if todo.screenshotPaths.count > 1 {
                            Text("\(todo.screenshotPaths.count)")
                        }
                    }
                    .dsTag(DS.Colors.text2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(todo.screenshotPaths.count > 1 ? "查看 \(todo.screenshotPaths.count) 张原始截图" : "查看原始截图")
            } else if let symbol = Self.sourceSymbol(todo.source) {
                Image(systemName: symbol)
                    .font(.system(size: 9))
                    .dsTag()
            }

            Spacer(minLength: 0)

            // 优先级徽章：行尾（time-first / priority-last）
            PanelPriorityTag(priority: todo.priority)

            // 截图来源：行尾缩略图（多图叠角标），点击用「预览」打开全部原图
            if !todo.screenshotPaths.isEmpty {
                ScreenshotThumb(paths: todo.screenshotPaths)
            }
            // 编辑 + 删除按钮（悬停显示）：编辑开编辑卡；删除时本地直接删、苹果来源项删前确认
            if hovering && !todo.isCompleted {
                Button { store.present(.editTask(todo: todo)) } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.text3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("编辑")
            }
            if hovering && store.canDelete(todo) {
                Button { requestDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.text3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(todo.source == .calendar ? "从苹果日历删除" : "删除")
            }
        }
        .padding(8)
        .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        // 整行（含右侧空白）参与命中测试，删除按钮不再只在文字上方才出现
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // 编辑/删除/改优先级都走编辑卡（行内右侧 icon 进入），不再用右键菜单
        .confirmationDialog(
            "从苹果日历删除「\(todo.title)」？此操作不可恢复。",
            isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { store.delete(todo) }
            Button("取消", role: .cancel) {}
        }
        // 弹窗期间抑制悬停移出自动收起（任何关闭路径都经此对称减计数）
        .onChange(of: confirmingDelete) { _, presented in
            store.dialogPresentedCount += presented ? 1 : -1
        }
    }

    /// 状态字形：完成绿勾（点击撤销）/ 可完成圈 / 未来·无截止的静态小点
    @ViewBuilder
    private var statusGlyph: some View {
        if todo.isCompleted {
            Button { store.uncomplete(todo) } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.success)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
        } else if store.canComplete(todo) {
            PanelCheckCircle(action: onComplete)
        } else {
            Circle()
                .fill(DS.Colors.text3.opacity(0.55))
                .frame(width: 5, height: 5)
                .frame(width: 16, height: 16)
        }
    }

    /// 时间轨：有有效截止显示时间，snooze 过的把铃铛放在时间「后面」——
    /// 这样所有行的 HH:mm 从列首同一位置起,带不带铃铛都对齐。
    /// 时间栏宽度（timeTrackWidth=56）已为 HH:mm+铃铛 预留空间，lineLimit 兜底防换行。
    @ViewBuilder
    private var timeTrack: some View {
        if let due = todo.effectiveDue {
            HStack(spacing: 3) {
                Text(timeLabel(due))
                if todo.snoozedUntil != nil {
                    Image(systemName: "bell.fill").font(.system(size: 8))
                }
            }
            .font(DS.Fonts.compactSide)
            .foregroundStyle(timeColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    /// 时间轨只承载时刻：任意一天都显示裸 HH:mm（与 MeetingRow 一致），
    /// 所属日期交给分组段头表达——不出现「明天 / 周X / M/d」等日期文案。
    private func timeLabel(_ due: Date) -> String {
        PanelFormat.hm(due)
    }

    /// 时间颜色：完成灰 / 超期红 / 常规与 MeetingRow 一致（text1）
    private var timeColor: Color {
        if todo.isCompleted { return DS.Colors.text3 }
        if todo.isOverdue { return DS.Colors.alert }
        return DS.Colors.text1
    }

    /// 苹果来源项删除前确认（真删苹果日历/提醒，不可恢复）；本地任务直接删
    private func requestDelete() {
        if todo.source == .calendar {
            confirmingDelete = true
        } else {
            store.delete(todo)
        }
    }

    /// 来源小图标（manual 不显示，对齐 prototype；jira 走独立分组）
    private static func sourceSymbol(_ source: TodoSource) -> String? {
        switch source {
        case .screenshot: "camera.fill"
        case .calendar: "calendar"
        case .manual: nil
        }
    }
}

// MARK: - 截图查看（单张/多张统一入口：用「预览」打开，多张落到同一个窗口）

enum ScreenshotViewer {
    /// 在灵动岛上层弹出大图查看器（独立透明窗口，层级高于岛）。多张图带翻页。
    /// 看图当作一次聚焦模态：打开期间置 `screenshotViewerOpen` 让灵动岛保持不动，
    /// 关闭时清零恢复正常收起 —— 生命周期由查看器回调驱动，完全可控。
    @MainActor static func open(_ paths: [String], store: AppStore) {
        ScreenshotViewerWindowController.shared.show(
            paths: paths,
            onWillOpen: { store.screenshotViewerOpen = true },
            onDidClose: { store.screenshotViewerOpen = false }
        )
    }
}

// MARK: - 截图缩略图（行尾，点击看原图；多图叠数量角标，点击打开全部）

struct ScreenshotThumb: View {
    let paths: [String]
    @EnvironmentObject var store: AppStore
    @State private var image: NSImage?
    @State private var missing = false
    @State private var hovering = false

    /// 缩略图取第一张；其余靠角标提示数量
    private var firstPath: String { paths.first ?? "" }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(hovering ? DS.Colors.text2 : DS.Colors.border, lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) { countBadge }
                    .onTapGesture { ScreenshotViewer.open(paths, store: store) }
                    .onHover { hovering = $0 }
                    .help(helpText)
            } else if missing {
                // 原图文件已被清理：降级为占位图标，不崩溃
                RoundedRectangle(cornerRadius: 4)
                    .fill(DS.Colors.surface1)
                    .frame(width: 38, height: 26)
                    .overlay(
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.text3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(DS.Colors.border, lineWidth: 1)
                    )
                    .help("原图已不可用")
            }
        }
        .task(id: firstPath) {
            let thumb = Self.thumbnail(for: firstPath)
            image = thumb
            missing = thumb == nil
        }
    }

    /// 多图右下角「N」角标
    @ViewBuilder private var countBadge: some View {
        if paths.count > 1 {
            Text("\(paths.count)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DS.Colors.text1)
                .padding(.horizontal, 3)
                .frame(minWidth: 12, minHeight: 12)
                .background(DS.Colors.islandBG.opacity(0.85), in: Capsule())
                .overlay(Capsule().stroke(DS.Colors.border, lineWidth: 0.5))
                .padding(2)
        }
    }

    private var helpText: String {
        paths.count > 1 ? "点击查看 \(paths.count) 张原始截图" : "点击查看原始截图"
    }

    /// 解码并缓存小尺寸缩略图（避免列表滚动反复解码原图）
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor private static func thumbnail(for path: String) -> NSImage? {
        if let hit = cache[path] { return hit }
        guard FileManager.default.fileExists(atPath: path),
              let full = NSImage(contentsOfFile: path) else { return nil }
        let targetW: CGFloat = 76 // 2x 显示尺寸
        let scale = targetW / max(full.size.width, 1)
        let size = NSSize(width: targetW, height: full.size.height * scale)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        full.draw(in: NSRect(origin: .zero, size: size))
        thumb.unlockFocus()
        cache[path] = thumb
        return thumb
    }
}

// MARK: - 工作项行（Jira ticket / GitHub PR，只读跳转）

struct WorkItemRow: View {
    let item: WorkItem
    @State private var hovering = false

    var body: some View {
        // 图标垂直居中：行高随标题换行变化，顶对齐会让图标吊在左上角
        HStack(alignment: .center, spacing: 10) {
            // 只读集成（不改外部状态），用静态品牌图标占住完成圈位置保持对齐
            BrandIcon(brand: item.source == .github ? .github : .jira, size: 11)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.key)
                        .font(DS.Fonts.compactSide.weight(.semibold))
                        .foregroundStyle(DS.Colors.accent)
                        .onTapGesture { open() }
                    Text(item.title)
                        .font(DS.Fonts.todoTitle)
                        .foregroundStyle(DS.Colors.text1)
                }
                HStack(spacing: 6) {
                    PanelPriorityTag(priority: item.priority)
                    if let status = item.status {
                        if status == "In Progress" {
                            Text(status).dsTag(DS.Colors.accent, bg: DS.Colors.accentSoft)
                        } else {
                            Text(status).dsTag()
                        }
                    }
                    if let sp = item.storyPointsLabel {
                        Text(sp).dsTag()
                    }
                    if let assigner = item.assigner {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill").font(.system(size: 8))
                            Text(assigner)
                        }
                        .font(DS.Fonts.meta)
                        .foregroundStyle(DS.Colors.text3)
                    }
                }
            }
            Spacer(minLength: 0)
            // 行尾跳转箭头（hover 才显示）
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.text3)
                .opacity(hovering ? 1 : 0)
                .onTapGesture { open() }
        }
        .padding(8)
        .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        // 整行可点：工作项只读，唯一动作就是跳转，不必让用户瞄准小字
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m))
        .onTapGesture { open() }
        .onHover { hovering = $0 }
    }

    private func open() {
        guard let url = item.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 会议行

struct MeetingRow: View {
    let meeting: Meeting
    /// 对应 .calendar 任务已完成（日历页签传入，today-tasks-schedule-reminders spec）
    var isCompleted: Bool = false
    @EnvironmentObject var store: AppStore
    @State private var hovering = false
    @State private var glowPulse = false
    @State private var confirmingDelete = false

    private var isOngoing: Bool { meeting.status == .ongoing && !isCompleted }

    private var dotColor: Color {
        switch meeting.status {
        case .ongoing: DS.Colors.success
        case .upcoming: DS.Colors.text2
        case .ended: DS.Colors.text3
        }
    }

    /// 距开始 ≤30 分钟视为「快到了」：状态点换成提醒铃铛
    private var isImminent: Bool {
        guard !meeting.isReminder, meeting.status == .upcoming else { return false }
        return meeting.start.timeIntervalSinceNow <= 30 * 60
    }

    /// 全天事件（00:00 起、23:59+ 止）：节假日/纪念日，不显示时间区间
    private var isAllDay: Bool {
        let cal = Calendar.current
        let s = cal.dateComponents([.hour, .minute], from: meeting.start)
        let e = cal.dateComponents([.hour, .minute], from: meeting.end)
        return s.hour == 0 && s.minute == 0 && e.hour == 23 && (e.minute ?? 0) >= 59
    }

    /// 时间轨文案：全天 → 「全天」；否则起始时间（agenda 扫读只需起点，省宽给标题）
    private var timeLabel: String {
        isAllDay ? "全天" : PanelFormat.hm(meeting.start)
    }

    /// 时间颜色编码状态：进行中绿 / 快到了蓝 / 其余常规
    private var timeColor: Color {
        if isCompleted { return DS.Colors.text3 }
        if isOngoing { return DS.Colors.success }
        if isImminent { return DS.Colors.accent }
        return DS.Colors.text1
    }

    var body: some View {
        HStack(spacing: PanelRowMetric.spacing) {
            // 状态字形区：仅真实状态才占位（进行中/快到了/已完成/提醒），
            // 普通事件留空 —— 去掉装饰性灰点，同时用空位保证标题左对齐
            statusGlyph
                .frame(width: PanelRowMetric.statusGlyphWidth)

            // 时间轨：等宽左对齐，所有行标题对齐到同一条竖线
            Text(timeLabel)
                .font(DS.Fonts.compactSide)
                .foregroundStyle(timeColor)
                .frame(width: PanelRowMetric.timeTrackWidth, alignment: .leading)

            Text(meeting.title)
                .font(DS.Fonts.todoTitle)
                .foregroundStyle(isCompleted ? DS.Colors.text3 : .white)
                .strikethrough(isCompleted, color: DS.Colors.text3)
                .lineLimit(1)
            if meeting.isReminder {
                Text("提醒").dsTag(DS.Colors.accent, bg: DS.Colors.accentSoft)
            } else if let platform = meeting.platform {
                Text(platform.label).dsTag()
            }
            Spacer(minLength: 0)
            if !meeting.isReminder, let link = meeting.link {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    Text("加入会议")
                        .font(DS.Fonts.tag)
                        .foregroundStyle(DS.Colors.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(DS.Colors.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            if meeting.isReminder, let link = meeting.link {
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            // 删除（悬停显示）：苹果来源项删除前确认，会真删苹果日历/提醒
            if hovering {
                Button { requestDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.text3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(meeting.eventIdentifier != nil ? "从苹果日历删除" : "删除")
            }
        }
        .padding(8)
        .background(
            hovering ? DS.Colors.surface1 : (isOngoing ? DS.Colors.success.opacity(0.06) : Color.clear),
            in: RoundedRectangle(cornerRadius: DS.Radius.m)
        )
        .overlay {
            // 进行中：细描边 + 呼吸微光
            if isOngoing {
                RoundedRectangle(cornerRadius: DS.Radius.m)
                    .strokeBorder(DS.Colors.success.opacity(glowPulse ? 0.4 : 0.15), lineWidth: 1)
            }
        }
        .shadow(color: isOngoing ? DS.Colors.success.opacity(glowPulse ? 0.3 : 0.1) : .clear, radius: 7)
        .onAppear {
            if isOngoing {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    glowPulse = true
                }
            }
        }
        // 整行（含右侧空白）参与命中测试，删除按钮不再只在文字上方才出现
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .opacity(isCompleted || meeting.status == .ended ? 0.65 : 1)
        .confirmationDialog(
            "从苹果日历删除「\(meeting.title)」？此操作不可恢复。",
            isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { store.deleteMeeting(meeting) }
            Button("取消", role: .cancel) {}
        }
        // 弹窗期间抑制悬停移出自动收起（任何关闭路径都经此对称减计数）
        .onChange(of: confirmingDelete) { _, presented in
            store.dialogPresentedCount += presented ? 1 : -1
        }
    }

    /// 苹果来源项删除前确认（真删苹果日历/提醒）；演示数据（无标识）直接删
    private func requestDelete() {
        if meeting.eventIdentifier != nil {
            confirmingDelete = true
        } else {
            store.deleteMeeting(meeting)
        }
    }

    /// 状态/完成字形（later-into-calendar）：
    /// 已完成→绿勾（点击撤销）；今天及更早的苹果项→可点击完成圈；未来项→静态小点。
    @ViewBuilder
    private var statusGlyph: some View {
        if isCompleted {
            Button { store.toggleMeetingCompleted(meeting) } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.success)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
        } else if store.isMeetingCompletable(meeting) {
            Button { store.toggleMeetingCompleted(meeting) } label: {
                Circle()
                    .strokeBorder(hovering ? DS.Colors.text1 : DS.Colors.text3, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
        } else {
            // 未来的苹果日历项：小点，不可完成
            Circle().fill(DS.Colors.text3.opacity(0.55)).frame(width: 5, height: 5)
        }
    }
}

// MARK: - 已完成行

private struct CompletedRow: View {
    let todo: Todo
    let onUncomplete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            // 反悔入口 1：悬停时勾变撤销图标（热区扩大，描边/小图标直接点不中）
            Button(action: onUncomplete) {
                Image(systemName: hovering ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(hovering ? DS.Colors.accent : DS.Colors.text3)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(-4) // 抵消热区 padding，对齐不变
            Text(todo.title)
                .font(DS.Fonts.todoTitle)
                .foregroundStyle(DS.Colors.text3)
                .strikethrough(true, color: DS.Colors.text3)
            Spacer(minLength: 0)
            // 反悔入口 2：悬停行尾出现明确的「撤销」按钮（可发现性）
            if hovering {
                Button(action: onUncomplete) {
                    Text("撤销")
                        .font(DS.Fonts.tag)
                        .foregroundStyle(DS.Colors.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(DS.Colors.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        .onHover { hovering = $0 }
    }
}

// MARK: - 完成圈

struct PanelCheckCircle: View {
    let action: () -> Void
    /// 已完成态：true 显示填充绿色对勾圈，false 显示空心圈
    var isDone: Bool = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // 未完成：空心圈；条件渲染放进 overlay/ZStack 内部，宿主身份稳定
                Circle()
                    .strokeBorder(hovering ? DS.Colors.text1 : DS.Colors.text3, lineWidth: 1.5)
                    .opacity(isDone ? 0 : 1)
                // 已完成：绿色对勾——与日历/任务完成态统一（checkmark.circle.fill @ 11pt）
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.success)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            // 形状的点击判定只算画了像素的区域——空心描边圆只有 1.5pt 的环可点。
            // 负 inset 只外扩命中区域(26×26)不占布局，保持与 Jira 行 16pt 图标列对齐
            .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.top, 1)
    }
}

// ============================================================
// 以下为 Panels 模块共享小组件
// ============================================================

// MARK: - Tab 行（Today/Settings 共用）

struct PanelTabBar: View {
    @EnvironmentObject var store: AppStore
    let current: PanelTab

    var body: some View {
        // 5 个 tab 单行放得下，不套 ScrollView——避免横滚手势吞掉拖动重排、且角标不被裁。
        // 拖动 tab 即可重排（settings 不参与）；右端 ＋/↻/⚙ 固定。
        HStack(spacing: 2) {
            ForEach(visibleTabs, id: \.self) { tab in
                PanelTabButton(
                    title: tab.title,
                    isActive: tab == current,
                    badge: tab == .messages ? (store.unprocessedMessageCount + store.unreadMentions.count)
                        : (tab == .agent ? store.waitingAgentCount : 0)
                ) {
                    guard tab != current else { return }
                    store.present(.expanded(tab: tab))
                }
                // 拖动重排（settings tab 固定不参与）
                .draggable(tab.rawValue) { dragChip(tab) }
                .dropDestination(for: String.self) { items, _ in
                    guard current != .settings, let raw = items.first,
                          let dragged = PanelTab(rawValue: raw) else { return false }
                    store.moveTab(dragged, before: tab)
                    return true
                }
            }
            Spacer(minLength: 8)
            if current != .settings {
                // 新建：手动输入 / ⌥Space 语音 / ⌘V 贴图识别（记住来源面板，完成后回面板）
                PanelIconButton(symbol: "plus") { store.presentQuickInput() }
                // 系统组：刷新（同步 Jira/日历）+ 设置
                PanelRefreshButton()
                PanelIconButton(symbol: "gearshape.fill") { store.present(.expanded(tab: .settings)) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    /// 拖动时跟随光标的小标签
    private func dragChip(_ tab: PanelTab) -> some View {
        Text(tab.title)
            .font(DS.Fonts.button)
            .foregroundStyle(DS.Colors.text1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.s))
    }

    private var visibleTabs: [PanelTab] {
        current == .settings ? PanelTab.allCases : store.orderedVisibleTabs
    }
}

struct PanelTabButton: View {
    let title: String
    let isActive: Bool
    /// 未处理计数（>0 时标题右上角红点角标，消息页签用）
    var badge: Int = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        // 用 onTapGesture 而非 Button：Button 会吞掉拖拽手势，导致 .draggable 不触发。
        // tap 与 drag 由系统按移动距离自动区分
        Text(title)
            .font(DS.Fonts.button)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false) // 标签恒单行，不换行不压缩
            .foregroundStyle(isActive ? DS.Colors.text1 : (hovering ? DS.Colors.text2 : DS.Colors.text3))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.s))
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(DS.Colors.alert, in: Capsule())
                        .offset(x: 2, y: -1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { action() }
            .onHover { hovering = $0 }
    }
}

/// 刷新按钮：立即同步 Jira/日历，刷新中转圈并禁用
struct PanelRefreshButton: View {
    @EnvironmentObject var store: AppStore
    @State private var hovering = false
    @State private var spinAngle = 0.0

    var body: some View {
        Button { store.refresh() } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(store.isRefreshing ? DS.Colors.accent : (hovering ? DS.Colors.text1 : DS.Colors.text3))
                .rotationEffect(.degrees(spinAngle))
                .frame(width: 26, height: 26)
                .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.s))
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing)
        .onHover { hovering = $0 }
        .onChange(of: store.isRefreshing) { _, refreshing in
            if refreshing {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            } else {
                withAnimation(.linear(duration: 0.1)) { spinAngle = 0 }
            }
        }
        .help("立即同步 Jira 与日历")
    }
}

struct PanelIconButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? DS.Colors.text1 : DS.Colors.text3)
                .frame(width: 26, height: 26)
                .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.s))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Section 标题（10pt semibold 大写 + 右侧计数 mono）

struct PanelSectionTitle: View {
    let title: String
    var count: Int?
    /// 标题色（已超期等强调段传 alert）
    var color: Color = DS.Colors.text3

    var body: some View {
        HStack {
            Text(title)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            if let count {
                Text("\(count)").font(DS.Fonts.tag)
            }
        }
        .font(DS.Fonts.sectionTitle)
        .foregroundStyle(color)
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - 段内细分隔（「无固定时间」）

struct PanelMiniDividerLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
            Text(text)
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
                .fixedSize()
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - 分隔线

struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Colors.border)
            .frame(height: 1)
            .padding(.top, 6)
            .padding(.bottom, 10)
    }
}

// MARK: - AI 建议条

struct PanelAISuggestion: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.Fonts.meta)
            .foregroundStyle(DS.Colors.accent)
            .lineSpacing(4)
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Colors.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.m))
    }
}

// MARK: - 优先级 tag

struct PanelPriorityTag: View {
    let priority: Priority

    var body: some View {
        // 红绿灯三档：高=红 / 中=橙 / 低=灰（配色统一走 DS.priorityTagFG/BG，全 app 一致）
        Text(priority.label)
            .dsTag(DS.priorityTagFG(priority), bg: DS.priorityTagBG(priority))
    }
}

// MARK: - 日期/时间格式化

enum PanelFormat {
    /// "HH:mm"
    static func hm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// 截止时间展示："今晚 18:00" / "今天 09:00" / "明天 12:00" / "6/15 周一"
    static func due(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let prefix = cal.component(.hour, from: date) >= 17 ? "今晚" : "今天"
            return "\(prefix) \(hm(date))"
        }
        if cal.isDateInTomorrow(date) { return "明天 \(hm(date))" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d EEE"
        return f.string(from: date)
    }

    /// "2026/06/12 星期五"
    static func fullDate(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy/MM/dd EEEE"
        return f.string(from: date)
    }
}
