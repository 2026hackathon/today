## Why

Today/任务列表的行首时间轨本应是一列「纯时钟」——和 `MeetingRow` 一样只显示具体几点。但个人任务行非当天的项走的是 `dsShortLabel`，会把时间丢掉、改吐出「明天 / 周X / M/d」这类相对日期词。结果同一段里时间轨忽而「09:00」忽而「明天」，列对不齐、信息还重复（日期已由分组段头给出）。要从源头保证：时间轨只出现具体时间或为空，永远不出现「明天」。

## What Changes

- 个人任务行（`PersonalTodoRow.timeLabel`）不再按「当天 HH:mm / 非当天 `dsShortLabel`」分叉：对任意一天的有效截止 SHALL 统一只渲染裸 `HH:mm`，日期一律交给分组段头表达。
- 时间轨的取值范围收敛为「具体时刻 `HH:mm`」或「空」二者其一——SHALL NOT 出现「明天 / 今天 / 昨天」等相对日期词，也 SHALL NOT 出现「周X / M/d」等日期串。
- 无有效截止时间的任务（`effectiveDue == nil`，含全天日历事件/无固定时间提醒）继续保留留空占位（既有行为，不变）。
- 不改数据模型、不改 `dsShortLabel` 本身（它在 HoverPreview / QuickInputCard 等带日期语境处仍正确），仅改任务行时间轨的取数来源，属纯展示层修正。

## Capabilities

### New Capabilities
<!-- 无新增能力，纯展示层修正 -->

### Modified Capabilities
- `island-shell`: 收紧「任务行统一布局」中**时间轨**的取值要求——时间轨 SHALL 仅显示具体时刻（`HH:mm`）或留空，SHALL NOT 出现相对日期词或日期串。

## Impact

- 代码：`MiniNotch/Sources/MiniNotch/UI/Panels/TodayPanel.swift`（`PersonalTodoRow.timeLabel`，约 335–338 行）。
- 行为：仅影响非当天个人任务行的时间轨文案；当天项、无截止项、日历/提醒行均不变。
- 无数据/持久化/同步影响；无 API 变更。`dsShortLabel` 的其余调用方不受影响。
