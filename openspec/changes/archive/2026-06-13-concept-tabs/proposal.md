## Why

页签结构应与「五大概念」一一对应，让用户在哪找什么一目了然。当前页签是历史演进的产物：`Later` 与 `Calendar` 职责重叠（later-into-calendar 后个人任务已进 Calendar 时间线，Later 只剩外部工单），且工作项（WorkItem）没有独立入口（活跃的散在 Today、积压的塞在 Later），个人任务也没有「全部待办」的纯列表入口。

与用户商定的最终结构：**Today（今日聚合）+ 每个概念一个 tab + 一个合并时间线 Calendar**。

## What Changes

- **删除 `Later`(Inbox) 页签**：其内容（外部工单积压）并入新的「工作项」页签。
- **新增「任务」页签（Todo）**：展示全部未完成个人任务的纯列表（可完成），区别于 Today（仅今日）与 Calendar（按时间线）。
- **新增「工作项」页签（WorkItem）**：展示全部 Jira/GitHub 工作项（活跃 + 积压分组），只读跳转。
- **新增「日历事件」页签（CalendarEvent）**：纯事件议程（会议/节假日），不含个人任务。
- **保留「Calendar」页签**：事件 + 个人任务的合并时间线（later-into-calendar，用户确认要保留）。
- **保留**「信息」(Message+Mention) 与 「Agent」(AgentSession) 页签。
- 最终页签：`Today · 任务 · 工作项 · 日历事件 · 信息 · Agent · Calendar`（+ ⚙）。
- **页签栏改横向可滚动**：7 个文本页签 + 右端固定 ＋/↻/⚙ 图标；用 `.scrollClipDisabled()` 防止角标被裁。

## Capabilities

### Modified Capabilities
- `island-shell`: 重定义展开态页签集合与各页签承载的概念；页签栏横向滚动、右端图标固定。

## Impact

- 代码：
  - `Island/IslandState.swift`（`PanelTab`：删 `.inbox`，加 `.tasks/.workItems/.events`；title/rawValue）
  - `Core/AppStore.swift`（`defaultTabs` 更新；`orderedVisibleTabs` 兼容旧 tabOrder）
  - `Island/IslandRootView.swift` + `UI/Panels/TodayPanel.swift`（新 tab 路由）
  - 新建 `UI/Panels/TasksPanel.swift` / `WorkItemPanel.swift` / `EventsPanel.swift`
  - `UI/Panels/InboxPanel.swift`（Later）废弃/删除
  - `UI/Panels/TodayPanel.swift` 的 `PanelTabBar`（横向滚动 + 固定右端图标）
- 数据：无模型变更；旧 `settings.tabOrder` 含已删页签 rawValue 时被过滤，新页签补到末尾。
