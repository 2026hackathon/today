# Proposal: agent-landed-jump

## Why

agent 一轮完成时除了铃铛计数 + 提示音，再给一张 jiraLanded 式的「已完成」通知卡，点击跳转到对应终端 session——你在别处工作时一眼看到哪个 agent 干完了、一点直达。

## What Changes

- hook / opencode 插件捕获终端定位信息（TERM_PROGRAM、__CFBundleIdentifier、ITERM_SESSION_ID、TMUX_PANE），写进事件
- `AgentSession` 携带终端引用；`IslandState` 新增 `agentLanded(session)` 卡片态（几何同 jiraLanded 380pt）
- 完成（转入 replied）且你不在该终端前台时，弹 agentLanded 卡（倒计时自动收回，与 jiraLanded 同款）
- 点击卡片跳转：tmux 选 pane / iTerm 选 session（AppleScript）/ 其它激活终端 App（bundle id）/ 兜底打开 cwd
- 完成提示音逻辑并入（已有），卡片 + 音一起

## Capabilities

### Modified Capabilities
- `agent-session`: 新增完成通知卡与终端跳转

### New Capabilities
（无）

## Impact

- Core/AgentSession.swift（终端字段）、IslandState（+1 case + 几何）、AppStore（onAgentReplied 带 session）
- AgentSessionService（hook/插件捕获 env + jumpTo 跳转）、AppDelegate、新增 UI/Cards/AgentLandedCard.swift
