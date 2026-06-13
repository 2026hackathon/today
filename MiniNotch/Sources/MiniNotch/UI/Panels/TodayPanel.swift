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
                    MessageInboxPanel()
                case .inbox:
                    InboxPanel()
                case .favorites:
                    PanelPlaceholder(tab: currentTab)
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
        if !store.todayMeetings.isEmpty { parts.append("\(store.todayMeetings.count) 场会议") }
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
                count: store.todayTimedTodos.count + store.todayUntimedTodos.count + store.todayExternalTodos.count
            )
            if store.todayTimedTodos.isEmpty && store.todayUntimedTodos.isEmpty && store.todayExternalTodos.isEmpty {
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
            // 外部只读项沉底（Jira/GitHub 不可完成，不挡可操作任务）
            if !store.todayExternalTodos.isEmpty {
                if !store.todayTimedTodos.isEmpty || !store.todayUntimedTodos.isEmpty {
                    PanelMiniDividerLabel(text: "Jira · GitHub")
                }
                ForEach(store.todayExternalTodos) { todo in
                    TaskRow(todo: todo)
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

// MARK: - 统一任务行（按来源分发：Jira 只读跳转，其余可完成）

struct TaskRow: View {
    let todo: Todo
    @EnvironmentObject var store: AppStore

    var body: some View {
        if todo.source == .jira || todo.source == .github {
            JiraTodoRow(todo: todo) // 外部只读 ticket 行（Jira/GitHub 共用）
        } else {
            PersonalTodoRow(todo: todo) { store.complete(todo) }
        }
    }
}

// MARK: - 个人 Todo 行

struct PersonalTodoRow: View {
    let todo: Todo
    let onComplete: () -> Void
    @EnvironmentObject var store: AppStore
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PanelCheckCircle(action: onComplete)
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .font(DS.Fonts.todoTitle)
                    .foregroundStyle(DS.Colors.text1)
                HStack(spacing: 6) {
                    PanelPriorityTag(priority: todo.priority)
                    if let due = todo.dueDate {
                        Text(PanelFormat.due(due))
                            .font(DS.Fonts.meta)
                            .foregroundStyle(todo.isOverdue ? DS.Colors.alert : DS.Colors.text3)
                    }
                    ForEach(todo.tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Image(systemName: "repeat").font(.system(size: 8))
                            Text(tag)
                        }
                        .dsTag()
                    }
                    if let symbol = Self.sourceSymbol(todo.source) {
                        Image(systemName: symbol)
                            .font(.system(size: 9))
                            .dsTag()
                    }
                }
            }
            Spacer(minLength: 0)
            // 截图来源：行尾缩略图，点击用「预览」打开原图
            if let path = todo.screenshotPath {
                ScreenshotThumb(path: path)
            }
        }
        .padding(8)
        .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        .onHover { hovering = $0 }
        // 右键：编辑（开编辑卡）/ 快速改优先级（无需进卡）/ 删除
        .contextMenu {
            Button("编辑…") { store.present(.editTask(todo: todo)) }
            Menu("优先级") {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button {
                        var t = todo; t.priority = p; store.update(t)
                    } label: {
                        Label(p.label, systemImage: todo.priority == p ? "checkmark" : "")
                    }
                }
            }
            Divider()
            Button("删除", role: .destructive) { store.delete(todo) }
        }
    }

    /// 来源小图标（manual 不显示，对齐 prototype；jira 走独立分组）
    private static func sourceSymbol(_ source: TodoSource) -> String? {
        switch source {
        case .screenshot: "camera.fill"
        case .calendar: "calendar"
        case .wechat: "message.fill"
        case .manual, .jira, .github: nil
        }
    }
}

// MARK: - 截图缩略图（行尾，点击看原图）

struct ScreenshotThumb: View {
    let path: String
    @State private var image: NSImage?
    @State private var hovering = false

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
                    .onTapGesture {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .onHover { hovering = $0 }
                    .help("点击查看原始截图")
            }
        }
        .task(id: path) {
            image = Self.thumbnail(for: path)
        }
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

// MARK: - Jira 行

struct JiraTodoRow: View {
    let todo: Todo
    @State private var hovering = false

    var body: some View {
        // 图标垂直居中：行高随标题换行变化，顶对齐会让图标吊在左上角
        HStack(alignment: .center, spacing: 10) {
            // Jira 是只读集成（PRD Out of Scope：不改 Jira 状态），
            // 不提供完成操作，用静态图标占住完成圈的位置保持对齐
            BrandIcon(brand: todo.source == .github ? .github : .jira, size: 11)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let key = todo.jiraKey {
                        Text(key)
                            .font(DS.Fonts.compactSide.weight(.semibold))
                            .foregroundStyle(DS.Colors.accent)
                            .onTapGesture { openJira() }
                    }
                    Text(todo.title)
                        .font(DS.Fonts.todoTitle)
                        .foregroundStyle(DS.Colors.text1)
                }
                HStack(spacing: 6) {
                    PanelPriorityTag(priority: todo.priority)
                    if let status = todo.jiraStatus {
                        if status == "In Progress" {
                            Text(status).dsTag(DS.Colors.accent, bg: DS.Colors.accentSoft)
                        } else {
                            Text(status).dsTag()
                        }
                    }
                    if let sp = todo.storyPointsLabel {
                        Text(sp).dsTag()
                    }
                    if let assigner = todo.jiraAssigner {
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
                .onTapGesture { openJira() }
        }
        .padding(8)
        .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        // 整行可点：Jira 行只读，唯一动作就是跳转，不必让用户瞄准小字
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m))
        .onTapGesture { openJira() }
        .onHover { hovering = $0 }
    }

    private func openJira() {
        guard let url = todo.jiraURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 会议行

struct MeetingRow: View {
    let meeting: Meeting
    /// 对应 .calendar 任务已完成（日历页签传入，today-tasks-schedule-reminders spec）
    var isCompleted: Bool = false
    @State private var hovering = false
    @State private var glowPulse = false

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
        HStack(spacing: 8) {
            // 状态字形区：仅真实状态才占位（进行中/快到了/已完成/提醒），
            // 普通事件留空 —— 去掉装饰性灰点，同时用空位保证标题左对齐
            statusGlyph
                .frame(width: 12)

            // 时间轨：等宽左对齐，所有行标题对齐到同一条竖线
            Text(timeLabel)
                .font(DS.Fonts.compactSide)
                .foregroundStyle(timeColor)
                .frame(width: 44, alignment: .leading)

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
        .onHover { hovering = $0 }
        .opacity(isCompleted || meeting.status == .ended ? 0.65 : 1)
    }

    /// 状态字形：只在有真实语义时渲染，普通事件返回空占位（标题靠空位对齐）
    @ViewBuilder
    private var statusGlyph: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.success)
        } else if isOngoing {
            // 进行中：绿点呼吸光晕
            Circle().fill(DS.Colors.success).frame(width: 6, height: 6)
                .shadow(color: DS.Colors.success.opacity(glowPulse ? 0.9 : 0.35), radius: glowPulse ? 4 : 2)
        } else if meeting.isReminder || isImminent {
            Image(systemName: "bell.fill")
                .font(.system(size: 9))
                .foregroundStyle(DS.Colors.accent)
        } else {
            Color.clear.frame(width: 6, height: 6)
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
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .strokeBorder(hovering ? DS.Colors.text1 : DS.Colors.text3, lineWidth: 1.5)
                .frame(width: 16, height: 16)
                // 形状的点击判定只算画了像素的区域——纯描边圆只有 1.5pt 的环可点。
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
        HStack(spacing: 2) {
            ForEach(visibleTabs, id: \.self) { tab in
                PanelTabButton(
                    title: tab.title,
                    isActive: tab == current,
                    badge: tab == .messages ? store.unprocessedMessageCount : 0
                ) {
                    guard tab != current else { return }
                    store.present(.expanded(tab: tab))
                }
            }
            Spacer(minLength: 0)
            if current != .settings {
                // 临时 Debug 入口：菜单栏图标可能被刘海吞掉找不到（hackathon 期间保留）
                PanelIconButton(symbol: "ladybug") {
                    (NSApp.delegate as? AppDelegate)?.showDebugMenuAtMouse()
                }
                // 创建组：贴图识别（兼容 CleanShot/微信等外部截图工具）+ 手动新建
                PanelIconButton(symbol: "doc.on.clipboard") { store.pasteScreenshot() }
                PanelIconButton(symbol: "plus") { store.present(.quickInput) }
                // 系统组：刷新（同步 Jira/日历）+ 设置
                PanelRefreshButton()
                PanelIconButton(symbol: "gearshape.fill") { store.present(.expanded(tab: .settings)) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var visibleTabs: [PanelTab] {
        current == .settings ? PanelTab.allCases : [.today, .calendar, .messages, .inbox, .favorites]
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
        Button(action: action) {
            Text(title)
                .font(DS.Fonts.button)
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
        }
        .buttonStyle(.plain)
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
        if priority == .high {
            Text(priority.label).dsTag(DS.Colors.alert, bg: DS.Colors.alertSoft)
        } else {
            Text(priority.label).dsTag()
        }
    }
}

// MARK: - Inbox/收藏 占位

struct PanelPlaceholder: View {
    let tab: PanelTab

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: tab == .inbox ? "tray" : "star")
                .font(.system(size: 24))
                .foregroundStyle(DS.Colors.text3)
            Text("\(tab.title) 等待接入")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text3)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
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
