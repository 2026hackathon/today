## 1. PanelTab 重构（IslandState.swift）

- [x] 1.1 `PanelTab` 删 `.inbox`，新增 `.tasks`(任务)/`.workItems`(工作项)/`.events`(日历事件)
- [x] 1.2 各 case 的 rawValue（稳定）与 title（任务/工作项/日历事件/Calendar…）

## 2. 默认集合与路由

- [x] 2.1 `AppStore.defaultTabs` = [today, tasks, workItems, events, messages, agent, calendar]
- [x] 2.2 `orderedVisibleTabs` 过滤掉旧 tabOrder 里已删的 .inbox，新 tab 补末尾
- [x] 2.3 `IslandRootView` 路由 `.events`（EventsPanel）；`.calendar` 维持 CalendarPanel
- [x] 2.4 `TodayPanel` body switch 路由 `.tasks`(TasksPanel)/`.workItems`(WorkItemPanel)；删 `.inbox`

## 3. 新建面板

- [x] 3.1 `TasksPanel`：全部未完成个人任务（personalTodos），可完成，空态文案
- [x] 3.2 `WorkItemPanel`：activeWorkItems + inboxWorkItems 分组（活跃/积压、Jira/GitHub），WorkItemRow，只读
- [x] 3.3 `EventsPanel`：纯事件议程（meetingsByDate 过滤掉 reminder？否——事件含会议/节假日，提醒已是 Todo），复用日期分组 + MeetingRow，不含 todo timeline
- [x] 3.4 删除/废弃 `InboxPanel`(Later)

## 4. 页签栏横向滚动（PanelTabBar）

- [x] 4.1 文本页签放进 `ScrollView(.horizontal)` + `.scrollClipDisabled()`（防角标裁剪）
- [x] 4.2 ＋/↻/⚙ 移出滚动区，固定在右端
- [x] 4.3 角标（messages/agent 计数）完整显示

## 5. 验收

- [x] 5.1 `swift build -c release` 通过
- [x] 5.2 打包签名重启冒烟：7 个页签可切换、横滚、角标完整；任务/工作项/日历事件内容正确；无 Later
- [x] 5.3 旧 tabOrder 含 .inbox 时启动不崩、被过滤
- [x] 5.4 `openspec validate concept-tabs` 通过
