## Why

日历页签当前有三处体验问题：删除苹果日程的二次确认弹窗还没等鼠标移到「删除」按钮，灵动岛就因悬停移出而自动收起、连带关掉了弹窗；行的删除按钮只有悬停到文字上才出现，空白区悬停无效；列表把 29 天历史数据全量铺开，信息过载且昨天的已完成项也混在其中。

## What Changes

- **修复弹窗误收起**：当任意确认弹窗（删除苹果日程/提醒的二次确认）打开时，抑制灵动岛的悬停移出自动收起，直到弹窗关闭。
- **扩大删除按钮悬停热区**：日历页签的任务行（`PersonalTodoRow`）与会议行（`MeetingRow`）整行（含右侧空白）均可触发悬停，删除按钮不再只在文字上方出现。
- **收窄日历列表时间窗**：日历页签只展示「昨天 ~ 未来 15 天」的数据（作用于展示层过滤，不改后台同步深度）；昨天的分组仅展示本地自定义且**未完成**的任务（不含苹果日程/会议，不含已完成项）；今天及未来照旧（含已完成、含苹果项）。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `island-shell`: 新增「确认弹窗打开时抑制悬停移出自动收起」的窗口行为约束。
- `apple-calendar-integration`: 新增日历页签展示时间窗「昨天 ~ 未来 15 天」并约束昨天的展示口径；新增行删除按钮悬停热区覆盖整行的约束。

## Impact

- `Island/IslandRootView.swift`：`handleHover` 移出收起的 guard 增加「弹窗打开」抑制条件。
- `Core/AppStore.swift`：新增 `@Published` 弹窗态标志（供悬停收起判定）；可能新增日历列表时间窗派生属性。
- `UI/Panels/TodayPanel.swift`：`PersonalTodoRow` / `MeetingRow` 增加整行 `contentShape`，确认弹窗开关同步置位弹窗态标志。
- `UI/Panels/CalendarPanel.swift`：`dayGroups` 按「昨天 ~ 未来 15 天」过滤并对昨天分组特判（展示层，不改同步常量）。
