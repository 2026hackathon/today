## 1. AppStore 会议查找

- [x] 1.1 在 `AppStore` 新增 `meeting(for todo: Todo) -> Meeting?`：仅当 `todo.source == .calendar` 且 `todo.calendarEventId != nil` 时，按 `eventIdentifier == calendarEventId` 在已加载 meetings 中匹配，否则返回 nil
- [x] 1.2 确认查找命中已同步会议（依赖 replaceMeetings 已填充 meetings 列表），无副作用、不触发同步

## 2. PersonalTodoRow 展示会议标签与加入入口

- [x] 2.1 在 `PersonalTodoRow`（`TodayPanel.swift`）解析对应 `Meeting`（通过 store 的查找），取 `platform` 与 `link`
- [x] 2.2 当 `platform != nil` 时，在既有 kind/重复标签旁渲染平台标签，复用 `MeetingRow` 的 `Text(platform.label).dsTag()` 视觉
- [x] 2.3 当 `link != nil` 时，提供「加入会议」入口（复用 `MeetingRow` 的打开链接行为），放置遵循行内既有控件（hover/对齐）约定，不挤压静止态布局
- [x] 2.4 严格门控：无匹配会议 / 无 platform / 无 link 时不渲染对应元素，确保行与改动前一致（无空标签、无失效按钮）

## 3. 验证

- [x] 3.1 `swift build` 通过
- [ ] 3.2 手动验证：带 Zoom/腾讯链接的当天日程在「今日任务」显示平台标签且「加入会议」可打开链接（需运行 app + 真实日历数据，待人工确认）
- [ ] 3.3 手动验证：提醒事项 / 无链接日程 / manual·screenshot 任务行渲染与改动前一致（需运行 app，待人工确认）
- [x] 3.4 `openspec validate today-show-meeting-link` 通过
