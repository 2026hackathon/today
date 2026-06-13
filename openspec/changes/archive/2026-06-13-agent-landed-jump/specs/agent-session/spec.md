# agent-session (delta)

## ADDED Requirements

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
