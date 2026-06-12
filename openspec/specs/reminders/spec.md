# reminders Specification

## Purpose
TBD - created by archiving change todoisland-framework. Update Purpose after archive.
## Requirements
### Requirement: 四级提醒调度
`ReminderScheduler` SHALL 按 提前 1h（弱）/ 提前 15min（中）/ 到期（强）/ 已过期（极强）四级触发回调，误差 < 30s；数据变化后 SHALL 重新调度。

#### Scenario: 到期触发
- **WHEN** 当前时间到达某 todo 的 dueDate
- **THEN** island 自动切换 reminder 卡片态 + 红色脉冲

### Requirement: Snooze
提醒卡片 SHALL 提供 5min / 15min / 1h / 明天 09:00 / 自定义 五个 Snooze 选项；Snooze 后 SHALL 记录次数并在到点后重新提醒（黄色脉冲区分）。

#### Scenario: Snooze 15 分钟
- **WHEN** 用户点击「15 分钟」
- **THEN** snoozedUntil = now+15min、snoozeCount+1、island 回到 compact 态

### Requirement: 勿扰时段
22:00–08:00（可配置）SHALL 不弹提醒卡片，仅更新 compact 态颜色。

#### Scenario: 深夜到期
- **WHEN** 23:00 有 todo 到期
- **THEN** 不弹卡片，compact 态转 urgent 色

### Requirement: Snooze 到点后的分级与输入态保护
snooze 到点后 SHALL 以 snooze 时间为有效截止走标准分级管线（due 一次 + 过期每 5 分钟重复），不得一次性提醒后永久静音；到期提醒与晚报 SHALL NOT 抢占输入态（快速新建/任务降落/批量卡），推送照发，晚报顺延到回到收缩态后弹出。

#### Scenario: snooze 过的任务持续过期
- **WHEN** 任务 snooze 15 分钟后到点且用户未处理
- **THEN** due 级提醒一次，之后每 5 分钟 overdue 级重复（与未 snooze 任务一致）

#### Scenario: 输入中晚报到点
- **WHEN** 18:00 到点时用户正在 ⌘N 输入
- **THEN** 晚报不弹出、当日标记不消耗，用户回到收缩态后下一分钟弹出

