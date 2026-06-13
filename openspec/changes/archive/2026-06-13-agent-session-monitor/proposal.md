# Proposal: agent-session-monitor

## Why

借鉴 Vibe Island：把 Claude Code 等 coding agent 的会话状态搬到刘海。最易实现也最高频的一块——**收缩态徽章**：左翼显示运行中的 agent 数，右翼显示「已回复 / 等待确认」需要你处理的会话数。你 fire 一个 agent 后切去干别的，瞥一眼刘海就知道有没有 agent 在等你。

## What Changes

- 新增 `AgentSession` 模型 + 状态机（working / waiting / replied / ended）
- `AppStore` 维护 `agentSessions`，派生 `activeAgentCount`（运行中）/ `waitingAgentCount`（已回复+等待确认），独立于 todo，不进任何列表
- 收缩态徽章（CompactContent）：左翼 active 计数（叠加在 inbox 计数旁），右翼 waiting 计数（优先于截止上下文展示）；有徽章时 compact 几何加宽
- 接入机制：生成 Claude Code hook 脚本（python3）→ 事件追加写 JSONL → `AgentSessionService` 用 DispatchSource 监听 → 驱动 store
- Settings/Debug：一键安装 hook（写 ~/.claude/settings.json，备份）+ Debug 注入假会话

## Capabilities

### New Capabilities
- `agent-session`: coding agent 会话状态采集与收缩态徽章展示

### Modified Capabilities
- `island-shell`: 收缩态几何在有 agent 徽章时加宽

## Impact

- 新增 Core/AgentSession.swift、Services/AgentSessionService.swift
- AppStore / IslandState 几何 / CompactContent / AppDelegate 小幅扩展
- 不改 todo 数据模型与列表
