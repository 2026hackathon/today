# reminders (delta)

## ADDED Requirements

### Requirement: Snooze 到点后的分级与输入态保护
snooze 到点后 SHALL 以 snooze 时间为有效截止走标准分级管线（due 一次 + 过期每 5 分钟重复），不得一次性提醒后永久静音；到期提醒与晚报 SHALL NOT 抢占输入态（快速新建/任务降落/批量卡），推送照发，晚报顺延到回到收缩态后弹出。

#### Scenario: snooze 过的任务持续过期
- **WHEN** 任务 snooze 15 分钟后到点且用户未处理
- **THEN** due 级提醒一次，之后每 5 分钟 overdue 级重复（与未 snooze 任务一致）

#### Scenario: 输入中晚报到点
- **WHEN** 18:00 到点时用户正在 ⌘N 输入
- **THEN** 晚报不弹出、当日标记不消耗，用户回到收缩态后下一分钟弹出
