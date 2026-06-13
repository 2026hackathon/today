# agent-session Specification

## Purpose
TBD - created by archiving change agent-session-monitor. Update Purpose after archive.
## Requirements
### Requirement: 会话状态采集
应用 SHALL 通过 Claude Code hook（写 JSONL 事件文件，应用监听）维护活跃 agent 会话集合，状态由 hook 事件驱动：UserPromptSubmit/SessionStart → working，Notification → waiting，Stop → replied，SessionEnd → 移除。未配置 hook 时集合为空，不报错。

#### Scenario: agent 开始运行
- **WHEN** Claude Code 收到一个 prompt 开始执行
- **THEN** 收缩态左翼出现 agent 图标 + 运行中会话数

#### Scenario: agent 等待你
- **WHEN** agent 请求权限/提问（Notification）或一轮回答结束（Stop）
- **THEN** 收缩态右翼显示「需要你处理」的会话数

### Requirement: 收缩态徽章
徽章 SHALL 叠加在现有收缩态内容上，独立于 todo 派生状态：左翼 active 计数与 inbox 计数并列；右翼 waiting 计数优先于截止上下文。计数为 0 时不显示对应徽章；有徽章时 compact 几何加宽以容纳。

#### Scenario: 无 agent 会话
- **WHEN** 没有任何活跃 agent 会话
- **THEN** 收缩态与现状一致（只显示 todo 相关内容）

### Requirement: 陈旧会话清理
应用 SHALL 周期清理陈旧会话（长时间无事件更新的 working 会话视为已结束），避免 agent 崩溃后徽章永久残留。

#### Scenario: agent 异常退出
- **WHEN** 某会话超过阈值无任何事件
- **THEN** 该会话从计数中移除

### Requirement: 完成通知卡与终端跳转
agent 会话转入 replied（一轮完成）且当前不在该会话所属终端前台时，SHALL 弹出 agentLanded 通知卡（agent 名 / 项目 / 已完成 + 倒计时自动收回，jiraLanded 同款）。卡片 SHALL 携带终端定位信息（由 hook/插件从环境变量捕获），点击 SHALL 尽力跳转到对应终端 session：tmux 选 pane、iTerm2 选 session、其它激活终端 App，最终兜底打开 cwd。捕获不到定位信息时只激活/兜底，不报错。

#### Scenario: 你在别处工作时 agent 完成
- **WHEN** agent 一轮完成且其终端不在前台
- **THEN** 浮起「已完成」卡，点击切到该终端（Warp 等无 pane API 的终端激活到前台）

#### Scenario: 你正盯着该终端
- **WHEN** 完成时该会话终端已在前台
- **THEN** 不弹卡（避免打扰），仅提示音

#### Scenario: iTerm/tmux 精确跳转
- **WHEN** 会话带 ITERM_SESSION_ID 或 TMUX_PANE
- **THEN** 跳转选中那个具体 session/pane，而非仅激活 App

