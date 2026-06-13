## Why

Jira ticket 与 GitHub PR 目前被硬塞进 `Todo`（`source = .jira/.github` + 复用 `jiraKey/jiraStatus/...` 字段），但它们与「个人待办」本质不同：

- **不可在 app 内完成**——只能跳转到外部系统处理（只读）；
- **生命周期由外部驱动**——To Do→In Progress→Done / PR review 状态，本地无主权；
- **数据整体替换**——每轮轮询拉取覆盖，不像个人任务由用户增删改。

为容纳它们，`AppStore` 被迫到处特判（`isExternal()`、`readOnlySources`、`isActiveJira()`、`todayExternalTodos`、`JiraTodoRow` 等），且导致计数语义混乱（如「今天 N 个任务」把只读工单也算进去）。这些特判都是「它本不该是 Todo」的征兆。

本次把 Jira/GitHub 抽取为独立概念 **WorkItem（工作项）**，使五大概念边界清晰、零重叠：
**Todo=要做完 · WorkItem=要推进 · CalendarEvent=要参加 · Message/Mention=要读 · AgentSession=要 review。**

## What Changes

- **新增 `WorkItem` 模型**：承载外部工单（Jira ticket / GitHub PR）的 key/title/status/statusCategory/assigner/storyPoints/url/priority/updatedAt 等，独立于 `Todo`。
- **`Todo` 瘦身**：移除 `jiraKey/jiraURL/jiraStatus/jiraStatusCategory/jiraAssigner/storyPoints` 等只服务于外部工单的字段；`TodoSource` 移除 `.jira/.github`，仅保留 `screenshot/manual/calendar`。
- **服务产出改变**：`JiraService.fetchAssignedTickets()` / `GitHubService.fetchMyPullRequests()` 返回 `[WorkItem]` 而非 `[Todo]`。
- **Store 派生重组**：`AppStore` 新增 `workItems` 数组与 `activeWorkItems`（Jira In Progress + GitHub 待 review/已指派）/`inboxWorkItems`（其余 To Do 等）派生；删除 `isActiveJira/isExternal/todayExternalTodos/readOnlySources` 等围绕 Todo 的外部特判，焦点计数（`todayFocusCount`/compact）改为「个人任务 + 活跃工作项」清晰相加。
- **UI 改写**：`JiraTodoRow` → `WorkItemRow`（吃 `WorkItem`）；Today 的「Jira · GitHub」分组、Later(Inbox) 页签改读 `workItems`；新 Jira 分配降落卡 `jiraLanded` 改携带 `WorkItem`。
- **持久化与迁移**：工作项存 `workItems.json`；启动时把 `todos.json` 里残留的 `.jira/.github` 旧记录迁移/丢弃（下一轮轮询即重建，无数据损失）。
- **BREAKING**（数据模型）：`Todo` 字段与 `TodoSource` 枚举变更——逐字段 `decodeIfPresent` 兼容旧 `todos.json`，旧外部记录解码后被迁移逻辑剔除。

## Capabilities

### New Capabilities
- `work-item`: 外部工单（Jira/GitHub）作为独立只读概念的模型、派生集合、展示与轮询合并规则。

### Modified Capabilities
- `todo-data`: `Todo` 不再承载外部工单字段；派生集合（焦点/Inbox/计数）改为个人任务，外部工单独立计入。
- `integrations`: Jira/GitHub 服务产出 `WorkItem`；同步镜像清理按 WorkItem 进行。

## Impact

- 代码：
  - `Core/Models.swift`（新增 `WorkItem`；`Todo` 移除 jira 字段；`TodoSource` 去 `.jira/.github`）
  - `Core/AppStore.swift`（`workItems` + 派生；移除外部特判；`mergeExternalTodos`→`mergeWorkItems`；持久化与迁移）
  - `Services/JiraService.swift` / `Services/GitHubService.swift`（返回 `[WorkItem]`；Mock 同步改造）
  - `AppDelegate.swift`（装配 onWorkItems 回调）
  - `UI/Panels/TodayPanel.swift`（`WorkItemRow`；Today 外部分组改读 workItems）、`UI/Panels/InboxPanel.swift`（Later 读 workItems）
  - `Island/IslandState.swift`（`jiraLanded` 关联类型 `WorkItem`）、对应 `UI/Cards/JiraLandedCard.swift`
- 依赖：仅既有 Jira/GitHub REST 拉取，无新增外部依赖；Mock 保留。
- 数据：新增 `workItems.json`；`todos.json` 旧外部记录迁移剔除（轮询重建）。
