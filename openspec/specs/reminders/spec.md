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

