# Agent 会话监控 — 配置指南

把 Claude Code / opencode 的会话状态搬到刘海:**左翼** `⚙ N` 显示运行中的 agent 数、`🔔 N` 显示已回复 / 等待确认（需要你处理）的数。两个工具的会话**汇总计数**。借鉴 Vibe Island,只通知、无双向操作。

> 前提:TodoIsland（MiniNotch）正在运行——它负责监听事件文件并刷新徽章。

---

## 一分钟配置

菜单栏 TodoIsland 图标 → **Debug 状态** 子菜单：

1. 点 **「安装 Claude Code Hook」** —— 配置 Claude Code
2. 点 **「安装 opencode 插件」** —— 配置 opencode
3. **重启 Claude Code / opencode**（hook 和插件在会话启动时加载，已开着的会话不生效）

之后正常开 coding 会话,刘海徽章就会实时反映。验证:用 `claude -p "回复ok"` 或 `opencode run "回复ok"` 起个一次性会话,徽章应短暂出现 `⚙ 1`。

---

## 它改了你机器上的什么

| 文件 | 作用 |
|------|------|
| `~/.claude/settings.json` | 注入 6 个 hook（SessionStart/UserPromptSubmit/Notification/Stop/SubagentStop/SessionEnd）。**安装前自动备份**到 `~/.claude/settings.mininotch-bak.json`，原有 hook 保留不覆盖 |
| `~/Library/Application Support/MiniNotch/claude-agent-hook.py` | Claude Code 的 hook 脚本（python3），把事件追加写到事件文件 |
| `~/.config/opencode/plugin/mininotch.ts` | opencode 插件，监听 `session.status` / `permission.updated` / `session.idle` 转成同格式事件 |
| `~/Library/Application Support/MiniNotch/agent-events.jsonl` | 统一事件文件,两个工具都往这写；App 用文件监听（秒级）消费 |

**依赖**:Claude Code hook 需要 `python3`（macOS 自带）；opencode 插件需要 opencode（实测 1.17.4）。

---

## 事件 → 徽章映射

| Claude Code hook | opencode event | 会话状态 | 徽章 |
|------------------|----------------|---------|------|
| SessionStart / UserPromptSubmit | session.status(busy) | 运行中 | 左翼 `⚙` |
| Notification | permission.updated | 等待确认 | 左翼 `🔔` |
| Stop / SubagentStop | session.idle | 已回复（等你 review） | 左翼 `🔔` |
| SessionEnd | —（opencode 无结束事件,靠陈旧清理） | 移除 | — |

陈旧兜底:agent 异常退出没发结束事件时,运行中会话超 30min / 其它超 2h 无更新自动从计数移除。

---

## 手动配置（不想用菜单 / 给其他 Mac）

**Claude Code** —— 编辑 `~/.claude/settings.json`,在 `hooks` 下为这几个事件加（路径含空格,命令里**必须带引号**）:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command",
        "command": "python3 '/Users/你的用户名/Library/Application Support/MiniNotch/claude-agent-hook.py'" } ] }
    ]
  }
}
```

其余 5 个事件（SessionStart / UserPromptSubmit / Notification / SubagentStop / SessionEnd）同理。脚本由 App 启动时自动生成,确保 TodoIsland 跑过一次。

**opencode** —— 插件文件已由 App 生成到 `~/.config/opencode/plugin/mininotch.ts`,直接重启 opencode 即可；拷到别的 Mac 时改一下文件里 `EVENTS` 常量的用户名路径。

---

## 卸载

- Claude Code:删掉 `~/.claude/settings.json` 里 command 含 `claude-agent-hook.py` 的 hook 条目（或还原备份 `settings.mininotch-bak.json`）
- opencode:删掉 `~/.config/opencode/plugin/mininotch.ts`
- 重启对应工具

---

## 常见问题

- **徽章不出现**:确认 ① TodoIsland 在运行 ② 已重启 Claude Code / opencode ③ `python3` 可用（`which python3`）
- **`SessionEnd hook failed: can't open file '.../Application'`**:hook 命令路径没加引号被空格截断 —— 用菜单重装,或手动给路径加单引号（此问题菜单安装已修复）
- **看不到运行中只看到铃铛**:正常 —— 一次性 `-p`/`run` 会话瞬间就 idle 了；交互式长会话才会持续显示 `⚙`
- **想清掉残留计数**:Debug 菜单「清空 Agent 会话」,或重启 TodoIsland（启动从事件文件末尾读,不回放历史）

---

实现见 `openspec/changes/archive/2026-06-13-agent-session-monitor/`，代码在 `Services/AgentSessionService.swift`、`Core/AgentSession.swift`、`UI/Compact/CompactContent.swift`。
