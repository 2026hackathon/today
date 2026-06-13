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

