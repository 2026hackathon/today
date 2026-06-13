import Foundation

// ============================================================
// Island 状态机 —— 与 prototype.html 的 STATES 一一对应。
// island 长什么样只由 IslandState 决定（island-shell spec）。
// ============================================================

enum PanelTab: String, CaseIterable, Sendable {
    case today = "Today"
    case calendar = "日历"
    case messages = "消息"
    case inbox = "Inbox"
    case favorites = "收藏"
    case settings = "设置"

    /// 显示名：统一中文，与正文（今日任务/建议…）一致，避免中英混排。
    /// rawValue 保持稳定不动（仅作内部标识）
    var title: String {
        switch self {
        case .today: "Today"   // 保留英文品牌标签（产品指定）
        case .calendar: "日历"
        case .messages: "消息"
        case .inbox: "收件箱"
        case .favorites: "收藏"
        case .settings: "设置"
        }
    }
}

enum IslandState: Equatable, Sendable {

    // ── 收缩态（由 AppStore 数据自动派生，不要手动设置）──
    case idle           // 0 待办
    case normal         // 有待办，无紧急
    case near           // 1h 内有截止
    case urgent         // 30min 内截止 / 已过期
    case aiWorking      // AI 解析中（彩虹流光）
    case justCompleted  // 完成闪光（短暂，1s 后回落）

    // ── 悬浮交互 ──
    case hoverPreview

    // ── 卡片态（事件触发）──
    case newTask(draft: TodoDraft)      // 任务降落卡
    case reminder(todo: Todo)           // 到期提醒卡
    case batch(drafts: [TodoDraft])     // 批量识别卡
    case quickInput                     // ⌘N 手动新建
    case editTask(todo: Todo)           // 编辑已有个人任务（标题/时间/优先级）
    /// 新 Jira 分配通知卡：纯通知无操作，倒计时后自动收入岛体
    /// moreCount = 同轮其余新分配数（>0 显示「等 N 条」）
    case jiraLanded(todo: Todo, moreCount: Int)
    /// 新邮件消息降落卡（沿用 jiraLanded 样式/倒计时）：点击打开链接并标记已处理
    /// moreCount = 同轮其余新消息数（>0 聚合显示「N 条新消息」）
    case messageLanded(message: Message, moreCount: Int)
    /// agent 一轮完成通知卡：倒计时自动收回，点击跳转对应终端 session
    case agentLanded(session: AgentSession)

    // ── 展开态 ──
    case expanded(tab: PanelTab)
    case morningReport(text: String)
    case eveningReport(text: String)

    // ── 庆祝（compact 显示皇冠，全屏烟花走独立窗口）──
    case celebrate

    /// 是否属于自动派生的收缩态（数据变化时允许被覆盖）
    var isCompact: Bool {
        switch self {
        case .idle, .normal, .near, .urgent, .aiWorking, .justCompleted, .celebrate:
            true
        default:
            false
        }
    }

    /// 展开/卡片态时点击外部 or esc 应回落到 compact
    var isDismissable: Bool { !isCompact }
}

// MARK: - 几何映射（数值来自 prototype.html 的 island 尺寸变体）

struct IslandGeometry: Equatable {
    var width: CGFloat
    /// nil = 高度由内容自适应（card/input 类）
    var height: CGFloat?
    var cornerRadius: CGFloat

    /// - Parameter agentBadgeWidth: 收缩态 agent 徽章需要的额外宽度（左翼并排的 ⚙/🔔，由计数决定）
    static func geometry(for state: IslandState, notchSize: CGSize, agentBadgeWidth: CGFloat = 0) -> IslandGeometry {
        // compact 态宽度不小于真实刘海，保证视觉上完全盖住刘海
        let compactW = max(notchSize.width, 200)
        let compactH = max(notchSize.height, 32)
        let badge = agentBadgeWidth

        switch state {
        case .idle:
            // 非活跃态收窄：内容只有「图标+数｜✓」，两翼各 ~55pt 足够，
            // 今日做完后刘海尽量低存在感（宽度变化由弹簧平滑过渡）
            return .init(width: compactW + 110 + badge, height: compactH, cornerRadius: DS.Radius.islandCompact)
        case .normal, .near, .urgent, .justCompleted, .celebrate:
            // 真刘海中央是摄像头，compact 内容显示在两侧"翅膀"（各 ~75pt）
            return .init(width: compactW + 150 + badge, height: compactH, cornerRadius: DS.Radius.islandCompact)
        case .aiWorking:
            return .init(width: compactW + 190 + badge, height: compactH, cornerRadius: DS.Radius.islandCompact)
        case .hoverPreview:
            // 与 compact 同宽：悬停时壳体只向下拉伸，不发生横向跳变
            return .init(width: compactW + 150, height: nil, cornerRadius: DS.Radius.island)
        case .newTask, .reminder, .jiraLanded, .messageLanded, .agentLanded:
            return .init(width: 380, height: nil, cornerRadius: DS.Radius.island)
        case .batch:
            return .init(width: 380, height: nil, cornerRadius: DS.Radius.island)
        case .quickInput, .editTask:
            return .init(width: 480, height: nil, cornerRadius: DS.Radius.island)
        case .expanded, .morningReport, .eveningReport:
            return .init(width: 460, height: 540, cornerRadius: DS.Radius.island)
        }
    }
}
