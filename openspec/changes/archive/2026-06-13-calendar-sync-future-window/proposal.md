## Why

`calendar-list-ux-window` 把日历页签的**展示窗**扩到了「昨天 ~ 未来 15 天」，但 EventKit 的**同步窗**从未跟着扩——`CalendarSyncConfig.syncDaysFuture = 7`（`CalendarService.swift:52`），拉取范围仅 `[today 00:00, today+8)`。结果 +8 ~ +15 天的苹果日历事件/提醒根本没被拉进来，展示窗里这段区间永远是空的，用户看不到未来的苹果日程。

`apple-calendar-integration` 主 spec 自身也已不自洽：`同步窗口` 要求写「未来 7 天」，而 `同步范围常量` 要求写 `calendarSyncDaysFuture = 6` / 范围 `[today-29, today+7]`，两条互相矛盾，且都与展示窗的 +15 对不齐。

## What Changes

- 将同步未来天数提升到 **15 天**，使同步窗覆盖展示窗的未来上界，+8 ~ +15 天的苹果事件/提醒能被拉取并展示。
- 同步下界保持「今天 00:00（不含历史）」不变——展示窗中「昨天」一段按既有约定只显示本地自建未完成项，不需要昨天的苹果数据。
- 修订 `apple-calendar-integration` 中互相矛盾的两条同步范围要求，统一为「今天 00:00 ~ 未来 15 天、不含历史」。

## Capabilities

### Modified Capabilities
- `apple-calendar-integration`: 同步未来窗 7→15，覆盖展示窗上界；消除「同步窗口 / 同步范围常量」两条要求互相矛盾的描述。

## Impact

- `MiniNotch/Sources/MiniNotch/Services/CalendarService.swift`：`CalendarSyncConfig.syncDaysFuture` 与注释。
- 不改同步下界、不引入历史回溯、不改展示窗逻辑（`CalendarPanel.dayGroups` 已支持 +15）。
- 同步事件/提醒条数随窗口增大略增，无 schema/接口变化。
