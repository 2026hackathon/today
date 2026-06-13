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

struct AgentSession: Identifiable, Equatable, Sendable {
    let id: String          // hook 的 session_id
    var agent: String       // "Claude Code" / "Codex" …
    var cwd: String?
    var state: AgentSessionState
    /// Notification 的 message（等待原因，如「需要权限运行 Bash」）
    var message: String?
    var updatedAt: Date

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
