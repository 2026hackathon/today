## Why

当天的日程（日历事件）和提醒事项目前只在 Today 面板的「今日日程」只读区和日历页签中展示，无法像任务一样被勾选完成。用户希望它们进入「今日任务」统一管理：完成后从列表消失，并且在日历页签中保留一个完成标记，让两个视图的状态保持一致。

## What Changes

- 当天的日历事件与提醒事项 SHALL 同步为 `.calendar` 来源的 Todo，出现在 Today 面板「今日任务」分组中（按开始/截止时间排序），可点击完成
- 点击完成后该项不再出现在「今日任务」（进入「已完成」折叠区，行为与普通任务一致）
- 提醒事项完成时 SHALL 回写 EventKit（`EKReminder.isCompleted = true`），避免下次同步复活
- 日历页签（CalendarPanel）的日程/提醒行 SHALL 在对应任务已完成时显示一个完成小图标（绿色对勾），标题加删除线弱化
- `Meeting` 模型 SHALL 携带稳定的 EventKit 标识（`ev.eventIdentifier` / `reminder.calendarItemIdentifier`），作为 Todo 合并与完成状态匹配的键
- Today 面板原「今日日程」独立区段移除，避免与「今日任务」中的日程项重复展示

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `todo-data`: 「今日任务」分组新增日历/提醒派生任务；新增 `.calendar` 来源的合并同步规则（按 eventIdentifier upsert、删除事件时 prune、已完成项不复活）；移除「今日日程」独立分组
- `apple-calendar-integration`: Meeting 映射携带稳定 eventIdentifier；提醒完成回写 EventKit；CalendarPanel 行展示完成小图标

## Impact

- `Core/Models.swift`：Meeting 增加 `eventIdentifier` 字段；Todo 增加 `calendarEventId` 字段
- `Core/AppStore.swift`：新增日历/提醒 → Todo 的合并逻辑（复用 `mergeExternalTodos` 模式）；派生集合调整（今日任务纳入 `.calendar` 任务、移除今日日程区段依赖）
- `Services/CalendarService.swift`：EKEvent/EKReminder 映射补充标识符；新增提醒完成回写接口
- `UI/Panels/TodayPanel.swift`：移除「今日日程」区段；`.calendar` 来源任务走可完成行样式
- `UI/Panels/CalendarPanel.swift` + `MeetingRow`：根据完成状态渲染对勾小图标
- 持久化兼容：todos.json / meetings.json 新增可选字段，旧数据解码不受影响
