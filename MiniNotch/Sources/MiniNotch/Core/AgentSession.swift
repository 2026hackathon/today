import Foundation

// ============================================================
// AgentSession —— coding agent（Claude Code 等）会话状态。
// 借鉴 Vibe Island：会话状态搬到刘海收缩态徽章。
// 独立于 todo，不进任何任务列表（瞬态监控数据）。
// ============================================================

enum AgentSessionState: String, Codable, Sendable {
    case working   // 运行中（左翼 active 计数）
    case waiting   // 请求权限/提问，等你确认（右翼）
    case replied   // 一轮回答结束，等你 review / 下一条 prompt（右翼）
    case ended     // 会话结束（从计数移除）

    /// 是否需要你处理（右翼「等待确认」计数）
    var needsAttention: Bool { self == .waiting || self == .replied }
}

/// 终端定位信息（hook/插件从所在终端环境变量捕获，用于点击跳转）
struct TerminalRef: Equatable, Sendable {
    var program: String?     // TERM_PROGRAM：WarpTerminal / iTerm.app / Apple_Terminal …
    var bundleID: String?    // __CFBundleIdentifier：dev.warp.Warp-Stable …（激活用）
    var itermSession: String? // ITERM_SESSION_ID：wNtNpN:UUID（iTerm 精确选中）
    var tmuxPane: String?    // TMUX_PANE：%3（tmux 精确选中）

    var isEmpty: Bool {
        (bundleID ?? "").isEmpty && (program ?? "").isEmpty
            && (itermSession ?? "").isEmpty && (tmuxPane ?? "").isEmpty
    }
}

struct AgentSession: Identifiable, Equatable, Sendable {
    let id: String          // hook 的 session_id
    var agent: String       // "Claude Code" / "Codex" …
    var cwd: String?
    var state: AgentSessionState
    /// Notification 的 message（等待原因，如「需要权限运行 Bash」）
    var message: String?
    var updatedAt: Date
    /// 终端定位（点击卡片跳转用，捕获不到则为 nil）
    var terminal: TerminalRef?
    /// 会话标题：Claude Code 取 UserPromptSubmit 的 prompt，opencode 取 session.title
    var title: String?

    /// 项目名（cwd 末段，用于通知/跳转展示）
    var project: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }
}

// MARK: - Hook 事件（JSONL 每行一条，AgentSessionService 解析）

struct AgentEvent: Decodable, Sendable {
    let event: String        // hook_event_name
    let session_id: String
    let cwd: String?
    let message: String?
    let agent: String?
    // 终端定位（hook/插件捕获，老事件缺失则为 nil）
    var term: String?
    var term_bundle: String?
    var iterm_session: String?
    var tmux_pane: String?
    var title: String?

    var terminal: TerminalRef? {
        let ref = TerminalRef(
            program: term, bundleID: term_bundle,
            itermSession: iterm_session, tmuxPane: tmux_pane
        )
        return ref.isEmpty ? nil : ref
    }

    /// hook 事件名 → 会话状态（nil = 不改变状态，如 PostToolUse）
    var mappedState: AgentSessionState? {
        switch event {
        case "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse":
            .working
        case "Notification":
            .waiting
        case "Stop", "SubagentStop":
            .replied
        case "SessionEnd":
            .ended
        default:
            nil
        }
    }
}
