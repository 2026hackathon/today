import Foundation

// ============================================================
// Island 状态机 —— 与 prototype.html 的 STATES 一一对应。
// island 长什么样只由 IslandState 决定（island-shell spec）。
// ============================================================

enum PanelTab: String, CaseIterable, Sendable {
    case today = "Today"
    case inbox = "Inbox"
    case favorites = "收藏"
    case settings = "设置"
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
    /// 新 Jira 分配通知卡：纯通知无操作，倒计时后自动收入岛体
    /// moreCount = 同轮其余新分配数（>0 显示「等 N 条」）
    case jiraLanded(todo: Todo, moreCount: Int)

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

    static func geometry(for state: IslandState, notchSize: CGSize) -> IslandGeometry {
        // compact 态宽度不小于真实刘海，保证视觉上完全盖住刘海
        let compactW = max(notchSize.width, 200)
        let compactH = max(notchSize.height, 32)

        switch state {
        case .idle, .normal, .near, .urgent, .justCompleted, .celebrate:
            // 真刘海中央是摄像头，compact 内容显示在两侧"翅膀"（各 ~75pt）
            return .init(width: compactW + 150, height: compactH, cornerRadius: DS.Radius.islandCompact)
        case .aiWorking:
            return .init(width: compactW + 190, height: compactH, cornerRadius: DS.Radius.islandCompact)
        case .hoverPreview:
            // 与 compact 同宽：悬停时壳体只向下拉伸，不发生横向跳变
            return .init(width: compactW + 150, height: nil, cornerRadius: DS.Radius.island)
        case .newTask, .reminder, .jiraLanded:
            return .init(width: 380, height: nil, cornerRadius: DS.Radius.island)
        case .batch:
            return .init(width: 380, height: nil, cornerRadius: DS.Radius.island)
        case .quickInput:
            return .init(width: 480, height: nil, cornerRadius: DS.Radius.island)
        case .expanded, .morningReport, .eveningReport:
            return .init(width: 460, height: 540, cornerRadius: DS.Radius.island)
        }
    }
}
