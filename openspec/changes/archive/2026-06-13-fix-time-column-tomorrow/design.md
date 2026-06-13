## Context

`PersonalTodoRow.timeLabel(_:)`（`TodayPanel.swift:335–338`）当前实现：

```swift
private func timeLabel(_ due: Date) -> String {
    Calendar.current.isDateInToday(due) ? PanelFormat.hm(due) : due.dsShortLabel
}
```

`dsShortLabel`（`CompactContent.swift:283`）是为「紧凑卡片带日期语境」设计的相对日期标签：明天→「明天」、2–6 天→「周X」、更远→「M/d」。它会丢弃时刻、只吐日期词。任务行把它当时间轨用，于是非当天的项显示「明天」而非具体时刻——这正是 bug。

时间轨的语义是「行首纯时钟列」，所属日期已由分组段头（`CalendarPanel`/Today 分段，如「明天 6月14日 周日」）承载，不应在每行重复。

## Goals / Non-Goals

**Goals:**
- 任务行时间轨从源头只产出 `HH:mm` 或空，杜绝「明天 / 周X / M/d」。
- 改动范围最小，纯展示层，不碰数据模型与 `dsShortLabel` 本身。

**Non-Goals:**
- 不改 `dsShortLabel`——HoverPreview / QuickInputCard / BatchCard / MentionsPanel / PrepReminderCard 等带日期语境处仍需要它的相对日期文案。
- 不引入 `isAllDay`/date-only 等新字段：无固定时间的项（全天日历事件、无时刻提醒）在入库时 `dueDate` 已为 `nil`（`AppStore.swift:868`、`CalendarService.swift:365`），`effectiveDue == nil` → 时间轨已留空，无需额外判定。

## Decisions

**决策：`timeLabel` 对任意一天统一返回 `PanelFormat.hm(due)`，去掉 `isDateInToday` 分叉与 `dsShortLabel`。**

```swift
/// 时间轨只承载时刻：任意一天都显示裸 HH:mm，所属日期交给分组段头。
private func timeLabel(_ due: Date) -> String { PanelFormat.hm(due) }
```

- 为什么不用 `PanelFormat.due(due)`（输出「明天 12:00」）？需求明确「时间栏不要明天」，带日期前缀仍违背，且与段头重复。
- 为什么不在 `dsShortLabel` 内部改？那会破坏其它带日期语境的调用方。源头是「任务行选错了格式化器」，而非 `dsShortLabel` 错。
- 无有效时间的项不经过 `timeLabel`（`timeTrack` 在 `effectiveDue == nil` 时走 `Color.clear` 占位分支），故「为空」一侧无需改动。

## Risks / Trade-offs

- [非当天项原先靠时间轨隐含「哪天」，现在只剩时刻] → 列表本就按日期分组并带段头，时刻 + 段头信息完整；且当天项一直就是这样，行为统一反而更一致。
- [若某任务存了 00:00 的「伪日期」`dueDate`，会显示「00:00」而非空] → 当前入库路径中无时刻的项一律 `dueDate=nil`，不会落到 00:00；如未来出现该情况另行处理，不在本次范围。
