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

    /// 终端友好名（Warp / Ghostty / iTerm …），拿不到则 nil
    var displayName: String? {
        guard let p = program, !p.isEmpty else { return nil }
        let s = p.lowercased()
        if s.contains("warp") { return "Warp" }
        if s.contains("iterm") { return "iTerm" }
        if s.contains("ghostty") { return "Ghostty" }
        if s.contains("wezterm") { return "WezTerm" }
        if s.contains("kitty") { return "kitty" }
        if s.contains("alacritty") { return "Alacritty" }
        if s == "vscode" { return "VS Code" }
        if s.contains("apple_terminal") || s == "terminal" { return "Terminal" }
        return p
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
    /// 你的提问（UserPromptSubmit 的 prompt），作 session 名兜底
    var title: String?
    /// 会话名：Claude Code custom-title/agentName，opencode session.title
    var name: String?
    /// agent 最后一条回复（完成卡次行展示，Claude Code 从 transcript 取）
    var answer: String?

    /// 卡片/列表主行：会话名 → 提问兜底
    var displayName: String? {
        if let n = name, !n.isEmpty { return n }
        if let t = title, !t.isEmpty { return t }
        return nil
    }

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
    var name: String?
    var answer: String?

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
        case "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
             // 子任务（Task 子 agent）完成 ≠ 整轮完成：父会话仍在跑，
             // 故归为 working（刷新存活、不触发「已完成」卡），只有顶层 Stop 才算完成。
             "SubagentStop":
            .working
        case "Notification":
            .waiting
        case "Stop":
            .replied
        case "SessionEnd":
            .ended
        default:
            nil
        }
    }
}
